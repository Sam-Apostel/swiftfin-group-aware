//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import FactoryKit
import Foundation
import JellyfinAPI
import Logging

/// Loads one Seerr title, resolves it against the Jellyfin library and handles
/// requesting it and tagging who it's for.
///
/// Request and audience actions run in the background and report through
/// `events`; only a failed `refresh` turns the screen into an error.
@MainActor
@Stateful
final class SeerrMediaDetailViewModel: ViewModel {

    @CasePathable
    enum Action {
        case refresh
        case removeAudience
        case requestMedia(seasons: [Int]?)
        case saveAudience(Set<String>)

        var transition: Transition {
            switch self {
            case .refresh:
                .to(.refreshing, then: .content)
                    .whenBackground(.refreshing)

            case .removeAudience, .saveAudience:
                .background(.updatingAudience)

            case .requestMedia:
                .background(.requesting)
            }
        }
    }

    enum BackgroundState {
        case refreshing
        case requesting
        case updatingAudience
    }

    enum Event {
        case audienceRemoved
        case audienceSaved(offerRequest: Bool)
        case failed(String)
        case requested
    }

    enum State {
        case content
        case error
        case initial
        case refreshing
    }

    let mediaType: SeerrMediaType
    let tmdbID: Int

    @Published
    private(set) var details: SeerrMediaDetails?
    /// Every stored user on this server, used to name audience members.
    @Published
    private(set) var householdUsers: [UserState] = []
    /// `false` when no Seerr server is configured for the current Jellyfin server.
    @Published
    private(set) var isSeerrConfigured: Bool = true
    /// The Jellyfin item as seen by the current (primary) user, if it is in the library.
    @Published
    private(set) var libraryItem: BaseItemDto?
    /// `true` while the TMDB → library fallback lookup runs.
    @Published
    private(set) var isLookingUpLibraryItem: Bool = false
    /// A request made from this screen, kept so the status flips before Seerr reports it.
    @Published
    private(set) var submittedRequest: SeerrRequest?
    @Published
    private(set) var hasSubmittedRequest: Bool = false
    @Published
    private(set) var watchlistEntry: AudienceWatchlistEntry?

    private var isSubmittingRequest = false
    private var libraryLookupTask: Task<Void, Never>?

    private var seerrService: SeerrService {
        Container.shared.seerrService()
    }

    private var watchlistStore: AudienceWatchlistStore {
        Container.shared.audienceWatchlistStore()
    }

    var entryID: String {
        AudienceWatchlistEntry.makeID(tmdbID: tmdbID, kind: entryKind, jellyfinItemID: nil)
    }

    private var entryKind: AudienceWatchlistEntry.MediaKind {
        switch mediaType {
        case .movie:
            .movie
        case .tv:
            .tv
        }
    }

    init(mediaType: SeerrMediaType, tmdbID: Int) {
        self.mediaType = mediaType
        self.tmdbID = tmdbID
        super.init()

        let entryID = entryID

        Container.shared
            .audienceWatchlistStore()
            .$entries
            .sink { [weak self] entries in
                self?.watchlistEntry = entries.first { $0.id == entryID }
            }
            .store(in: &cancellables)

        // Load as soon as Seerr gets connected from the "not connected" state
        Container.shared
            .seerrService()
            .$client
            .dropFirst()
            .sink { [weak self] client in
                guard let self, client != nil, !self.isSeerrConfigured else { return }

                self.refresh()
            }
            .store(in: &cancellables)
    }

    // MARK: - Derived State

    var year: Int? {
        Self.releaseYear(from: details?.releaseDate)
    }

    private static func releaseYear(from releaseDate: String?) -> Int? {
        guard let releaseDate, releaseDate.count >= 4 else { return nil }

        return Int(releaseDate.prefix(4))
    }

    private var mediaStatus: SeerrMediaStatus {
        details?.mediaInfo?.status ?? .unknown
    }

    private var activeRequest: SeerrRequest? {
        details?.mediaInfo?.requests?.first { request in
            request.status == .pending || request.status == .approved
        }
    }

    var status: SeerrMediaDetailStatus {
        if libraryItem != nil {
            return mediaStatus == .partiallyAvailable ? .partiallyAvailable : .available
        }

        switch mediaStatus {
        case .available:
            return .available
        case .blocklisted:
            return .blocklisted
        case .partiallyAvailable:
            return .partiallyAvailable
        case .pending:
            return .requested
        case .processing:
            return .processing
        case .deleted, .unknown:
            return hasSubmittedRequest || activeRequest != nil ? .requested : .notRequested
        }
    }

    /// Whether the primary action should offer to request the title.
    var canRequest: Bool {
        switch status {
        case .notRequested:
            true
        case .partiallyAvailable:
            mediaType == .tv && !hasSubmittedRequest
        case .available, .blocklisted, .processing, .requested:
            false
        }
    }

    var requesterName: String? {
        submittedRequest?.requestedBy?.displayName ?? activeRequest?.requestedBy?.displayName
    }

    /// The Jellyfin user a request is made as; `nil` without a user session.
    ///
    /// - iOS: the primary user.
    /// - tvOS: a grown-up on the couch when the primary is a kid (kid-safe browsing),
    ///   see `SeerrService.requesterJellyfinUserID(for:)`.
    var requesterJellyfinUserID: String? {
        guard let userSession else { return nil }

        #if os(tvOS)
        return seerrService.requesterJellyfinUserID(for: userSession.couch)
        #else
        return userSession.user.id
        #endif
    }

    /// Seasons that can be picked in the TV request sheet (specials and empty seasons are skipped, like Seerr does).
    var requestableSeasons: [SeerrSeason] {
        (details?.seasons ?? [])
            .filter { $0.seasonNumber > 0 && ($0.episodeCount ?? 1) > 0 }
            .sorted { $0.seasonNumber < $1.seasonNumber }
    }

    /// The picker's pre-selection: the saved audience, else the current couch.
    var suggestedAudience: Set<String> {
        if let watchlistEntry {
            return watchlistEntry.audience
        }

        return userSession?.couch.memberIDs ?? []
    }

    // MARK: - Refresh

    @Function(\Action.Cases.refresh)
    private func _refresh() async throws {
        let session = try requireUserSession()

        // Every stored user on this server (no keychain access), to name audience members.
        let otherUsers = StoredValues[.User.users]
            .filter { $0.serverID == session.server.id && $0.id != session.user.id }

        householdUsers = [session.user] + otherUsers
        watchlistEntry = watchlistStore.entry(id: entryID)

        // Pick up audiences tagged on other devices (throttled to once a minute);
        // `watchlistEntry` follows the store.
        Task {
            await AudienceWatchlistActions.refreshIfNeeded()
        }

        guard let client = seerrService.client else {
            isSeerrConfigured = false
            throw SeerrError.notConfigured
        }

        isSeerrConfigured = true

        let details = try await client.details(mediaType: mediaType, tmdbID: tmdbID)
        let libraryItem = await seerrLibraryItem(details: details, session: session)

        self.details = details

        if let libraryItem {
            libraryLookupTask?.cancel()
            isLookingUpLibraryItem = false
            self.libraryItem = libraryItem
        } else {
            lookUpLibraryItem(details: details, session: session)
        }
    }

    /// The Jellyfin item Seerr links to (`jellyfinMediaId`), if the current user can see it.
    private func seerrLibraryItem(details: SeerrMediaDetails, session: UserSession) async -> BaseItemDto? {
        guard let itemID = details.mediaInfo?.jellyfinMediaId, itemID.isNotEmpty else { return nil }

        do {
            let request = Paths.getItem(itemID: itemID, userID: session.user.id)
            return try await session.client.send(request).value
        } catch {
            logger.warning(
                "Seerr's Jellyfin item is not reachable for the current user",
                metadata: [
                    "itemID": .string(itemID),
                    "error": .string(error.localizedDescription),
                ]
            )
            return nil
        }
    }

    /// Falls back to the watchlist store's TMDB → item map (covers titles Seerr hasn't synced yet).
    ///
    /// Runs after the screen is shown: building the map can take a moment the first time.
    private func lookUpLibraryItem(details: SeerrMediaDetails, session: UserSession) {
        let probe = makeEntry(
            details: details,
            audience: [],
            addedBy: session.user.id,
            jellyfinItemID: nil
        )
        let store = watchlistStore

        libraryLookupTask?.cancel()
        isLookingUpLibraryItem = true

        libraryLookupTask = Task { [weak self] in
            let items = await store.libraryItems(for: [probe], session: session)

            guard let self, !Task.isCancelled else { return }

            self.libraryItem = items[probe.id]
            self.isLookingUpLibraryItem = false
        }
    }

    private func reloadDetails(client: SeerrClient) async {
        do {
            details = try await client.details(mediaType: mediaType, tmdbID: tmdbID)
        } catch {
            logger.warning(
                "Failed to reload Seerr details",
                metadata: ["error": .string(error.localizedDescription)]
            )
        }
    }

    // MARK: - Request

    @Function(\Action.Cases.requestMedia)
    private func _requestMedia(_ seasons: [Int]?) async {
        guard !isSubmittingRequest else { return }

        isSubmittingRequest = true
        defer { isSubmittingRequest = false }

        guard let client = seerrService.client else {
            events.send(.failed(SeerrError.notConfigured.localizedDescription))
            return
        }

        do {
            let session = try requireUserSession()
            let requestedSeasons = mediaType == .tv ? seasons : nil

            // The requester's own Quick Connect session, else the API key as them
            // (or as the key owner when they have no Seerr account).
            let request = try await seerrService.perform(
                asJellyfinUserID: requesterJellyfinUserID ?? session.user.id,
                fallbackToAPIKeyOwner: true
            ) { userClient in
                try await userClient.request(
                    mediaType: mediaType,
                    tmdbID: tmdbID,
                    seasons: requestedSeasons
                )
            }

            submittedRequest = request
            hasSubmittedRequest = true
            events.send(.requested)

            // `perform` may have renewed an expired browsing session: prefer the current client
            await reloadDetails(client: seerrService.client ?? client)
        } catch {
            // 409: someone already requested it, which is what the user wanted.
            if case let .server(status, _)? = error as? SeerrError, status == 409 {
                hasSubmittedRequest = true
                events.send(.requested)

                await reloadDetails(client: seerrService.client ?? client)
                return
            }

            logger.error(
                "Failed to request Seerr media",
                metadata: [
                    "tmdbID": .stringConvertible(tmdbID),
                    "error": .string(error.localizedDescription),
                ]
            )
            events.send(.failed(error.localizedDescription))
        }
    }

    // MARK: - Audience

    @Function(\Action.Cases.saveAudience)
    private func _saveAudience(_ audience: Set<String>) async {
        guard audience.isNotEmpty else {
            await removeEntry()
            return
        }

        do {
            let session = try requireUserSession()

            guard let details else {
                throw ErrorMessage(L10n.unknownError)
            }

            let previousAudience = watchlistEntry?.audience ?? []

            var entry = watchlistEntry ?? makeEntry(
                details: details,
                audience: audience,
                addedBy: session.user.id,
                jellyfinItemID: libraryItem?.id
            )
            entry.audience = audience
            entry.title = details.title
            entry.year = Self.releaseYear(from: details.releaseDate) ?? entry.year
            entry.posterPath = details.posterPath ?? entry.posterPath
            entry.jellyfinItemID = libraryItem?.id ?? entry.jellyfinItemID
            entry.isDeleted = false

            try await watchlistStore.upsert(entry, sessions: session.householdSessions())

            watchlistEntry = watchlistStore.entry(id: entry.id) ?? entry
            events.send(.audienceSaved(offerRequest: status == .notRequested && !isLookingUpLibraryItem))

            await syncSeerrWatchlists(
                adding: audience,
                removing: previousAudience.subtracting(audience),
                title: details.title
            )
        } catch {
            logger.error(
                "Failed to save the audience",
                metadata: ["error": .string(error.localizedDescription)]
            )
            events.send(.failed(error.localizedDescription))
        }
    }

    @Function(\Action.Cases.removeAudience)
    private func _removeAudience() async {
        await removeEntry()
    }

    private func removeEntry() async {
        do {
            let session = try requireUserSession()
            let previousAudience = watchlistEntry?.audience ?? []

            try await watchlistStore.remove(entryID: entryID, sessions: session.householdSessions())

            watchlistEntry = nil
            events.send(.audienceRemoved)

            if let details {
                await syncSeerrWatchlists(
                    adding: [],
                    removing: previousAudience,
                    title: details.title
                )
            }
        } catch {
            logger.error(
                "Failed to remove the watchlist entry",
                metadata: ["error": .string(error.localizedDescription)]
            )
            events.send(.failed(error.localizedDescription))
        }
    }

    /// Best effort: mirror the audience into each member's own Seerr watchlist, so Seerr matches.
    private func syncSeerrWatchlists(
        adding: Set<String>,
        removing: Set<String>,
        title: String
    ) async {
        guard seerrService.isConfigured else { return }

        for jellyfinUserID in adding.union(removing).sorted() {
            let isAdding = adding.contains(jellyfinUserID)

            // Each member's own Quick Connect session, else the API key as them.
            // Throws when the person can't act on Seerr (not signed in / no account).
            do {
                try await seerrService.perform(asJellyfinUserID: jellyfinUserID) { userClient in
                    if isAdding {
                        try await userClient.addToWatchlist(
                            mediaType: mediaType,
                            tmdbID: tmdbID,
                            title: title
                        )
                    } else {
                        try await userClient.removeFromWatchlist(
                            mediaType: mediaType,
                            tmdbID: tmdbID
                        )
                    }
                }
            } catch {
                logger.warning(
                    "Failed to sync a Seerr watchlist",
                    metadata: [
                        "jellyfinUserID": .string(jellyfinUserID),
                        "error": .string(error.localizedDescription),
                    ]
                )
            }
        }
    }

    private func makeEntry(
        details: SeerrMediaDetails,
        audience: Set<String>,
        addedBy: String,
        jellyfinItemID: String?
    ) -> AudienceWatchlistEntry {
        let now = Date.now

        return AudienceWatchlistEntry(
            id: entryID,
            tmdbID: tmdbID,
            kind: entryKind,
            jellyfinItemID: jellyfinItemID,
            title: details.title,
            year: Self.releaseYear(from: details.releaseDate),
            posterPath: details.posterPath,
            audience: audience,
            addedBy: addedBy,
            addedAt: now,
            updatedAt: now,
            isDeleted: false
        )
    }
}
