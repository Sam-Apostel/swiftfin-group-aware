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
///
/// Kid safety (#50): a request never goes out as a restricted member while a grown-up is on the couch,
/// and never for a title above kid level while a child is on the couch (`requestGate`).
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
    /// The requester's name when a request from this screen went out as someone other than the primary user.
    @Published
    private(set) var requestedAsName: String?
    /// The person being signed in to Seerr (Quick Connect) before a request, if any.
    @Published
    private(set) var signingInName: String?
    @Published
    private(set) var watchlistEntry: AudienceWatchlistEntry?

    private var isSubmittingRequest = false
    private var libraryLookupTask: Task<Void, Never>?
    /// The latest Seerr watchlist mirror. Each new one waits for it, so a quick save-then-remove
    /// reaches Seerr in that order. Retained so it isn't tied to the screen's lifetime.
    private var watchlistSyncTask: Task<Void, Never>?

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

        // The requester (and so the request gate) follows Seerr sign-ins and the API key
        Container.shared
            .seerrService()
            .objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
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

    private var hasDeclinedRequest: Bool {
        details?.mediaInfo?.requests?.contains { $0.status == .declined } ?? false
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
            if let request = submittedRequest ?? activeRequest {
                return request.status == .approved ? .processing : .requested
            }

            if hasSubmittedRequest {
                return .requested
            }

            return hasDeclinedRequest ? .declined : .notRequested
        }
    }

    /// Whether the title is in a state that can be requested (before the couch's `requestGate`).
    var canRequest: Bool {
        switch status {
        case .declined, .notRequested:
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

    // MARK: - Requester

    /// The Jellyfin user a request is made as; `nil` without a user session.
    ///
    /// A grown-up on the couch when the primary is restricted (e.g. kid-safe browsing),
    /// see `SeerrService.requesterJellyfinUserID(for:)`.
    var requesterJellyfinUserID: String? {
        guard let userSession else { return nil }

        return seerrService.requesterJellyfinUserID(for: userSession.couch)
    }

    /// The couch member a request goes out as.
    var requester: UserState? {
        guard let requesterID = requesterJellyfinUserID else { return nil }

        return userSession?.couch.members.first { $0.id == requesterID }
    }

    /// Nobody on the couch who may request can act on Seerr: the request would go out as a restricted member.
    var isRequestBlocked: Bool {
        requester?.isRestricted ?? false
    }

    /// The requester's name when it isn't the primary user ("Requesting as Sam").
    var requestingAsName: String? {
        guard let requester,
              let primary = userSession?.couch.primary,
              requester.id != primary.id
        else { return nil }

        return requester.username
    }

    // MARK: - Kids

    /// The children on the couch (`UserState.isChildAudience`), in couch order.
    var childMembers: [UserState] {
        userSession?.couch.members.filter(\.isChildAudience) ?? []
    }

    /// Kid mode: a child is on the couch, whatever the kid-safe browsing setting.
    var isKidMode: Bool {
        userSession?.couch.hasChild ?? false
    }

    /// The title's certification is above kid level (or unknown).
    var isAboveKidLevel: Bool {
        SeerrCertification.isAboveKidLevel(details?.certification)
    }

    /// Whether Request may be offered to this couch.
    var requestGate: SeerrRequestGate {
        if isKidMode, isAboveKidLevel {
            return .notWithChild
        }

        return isRequestBlocked ? .askAGrownUp : .allowed
    }

    /// "Not while Tuur is on the couch".
    var notWithChildMessage: String {
        let names = childMembers.map(\.username)

        return L10n.SeerrDetail.notWhileOnTheCouch(
            ListFormatter.localizedString(byJoining: names),
            count: names.count
        )
    }

    /// The restricted members on the couch: who "Ask a grown-up" saves the title for.
    private var restrictedMemberIDs: Set<String> {
        Set(userSession?.couch.members.filter(\.isRestricted).map(\.id) ?? [])
    }

    /// "Ask a grown-up" was pressed (or someone already tagged it for them): the entry contains a kid.
    var hasAskedAGrownUp: Bool {
        guard let watchlistEntry else { return false }

        return !watchlistEntry.audience.isDisjoint(with: restrictedMemberIDs)
    }

    /// Seasons that can be picked in the TV request sheet (specials and empty seasons are skipped, like Seerr does).
    var requestableSeasons: [SeerrSeason] {
        (details?.seasons ?? [])
            .filter { $0.seasonNumber > 0 && ($0.episodeCount ?? 1) > 0 }
            .sorted { $0.seasonNumber < $1.seasonNumber }
    }

    /// The picker's pre-selection: the saved audience, else the current couch.
    ///
    /// With a child on the couch and a title above kid level, the children are left out.
    var suggestedAudience: Set<String> {
        if let watchlistEntry {
            return watchlistEntry.audience
        }

        return couchAudience
    }

    /// The couch members, minus the children when the title is above kid level.
    private var couchAudience: Set<String> {
        guard let couch = userSession?.couch else { return [] }
        guard isAboveKidLevel else { return couch.memberIDs }

        return Set(couch.members.filter { !$0.isChildAudience }.map(\.id))
    }

    // MARK: - Request Helpers

    /// Requests the title as `requester`, first signing them in to Seerr with Quick Connect
    /// when there is no API key and they have no Seerr session yet. Nothing to type.
    ///
    /// Both platforms' Request and "Request it too?" (after the season picker) go through here.
    /// Failures are reported as `.failed` events. Does nothing unless `requestGate` is `.allowed`.
    func submitRequest(seasons: [Int]?) {
        guard requestGate == .allowed,
              signingInName == nil,
              !background.is(.requesting)
        else { return }
        guard let requester,
              !seerrService.hasAPIKey,
              !seerrService.signedInUserIDs.contains(requester.id)
        else {
            requestMedia(seasons: seasons)
            return
        }

        let service = seerrService
        signingInName = requester.username

        // Keeps the view model alive until the request went out: the person pressed Request.
        Task { @MainActor in
            do {
                try await service.signInWithQuickConnect(jellyfinUserID: requester.id)
                self.signingInName = nil

                // In this async context the generated async overload is picked: it needs `await`.
                await self.requestMedia(seasons: seasons)
            } catch {
                self.signingInName = nil
                self.logger.error(
                    "Failed to sign the requester in to Seerr",
                    metadata: [
                        "jellyfinUserID": .string(requester.id),
                        "error": .string(error.localizedDescription),
                    ]
                )
                self.events.send(.failed(error.localizedDescription))
            }
        }
    }

    /// "Ask a grown-up": saves the title for the kids on the couch (the existing audience plus the kids),
    /// so a grown-up sees it on the watchlist. Repeat presses do nothing.
    func saveForAGrownUp() {
        guard requestGate == .askAGrownUp,
              !hasAskedAGrownUp,
              !background.is(.updatingAudience)
        else { return }

        let audience = (watchlistEntry?.audience ?? suggestedAudience).union(restrictedMemberIDs)

        guard audience.isNotEmpty else { return }

        saveAudience(audience)
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
        // Kid safety: never as a restricted member while a grown-up is here, never above kid level with a child.
        guard requestGate == .allowed else {
            logger.warning("Refused a Seerr request the couch may not make")
            return
        }
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
            let requestingAsName = requestingAsName

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
            requestedAsName = requestingAsName
            events.send(.requested)

            await tagForCouch(session: session)

            // `perform` may have renewed an expired browsing session: prefer the current client
            await reloadDetails(client: seerrService.client ?? client)
        } catch {
            // 409: someone already requested it, which is what the user wanted.
            if case let .server(status, _)? = error as? SeerrError, status == 409 {
                hasSubmittedRequest = true
                events.send(.requested)

                if let session = userSession {
                    await tagForCouch(session: session)
                }

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

    /// After a group request: tags the title for the couch, so "Just arrived" and the
    /// ready banner show it to everyone who was there (not only the requester).
    ///
    /// Only without an existing entry, and only on a group couch. Children are left out above kid level.
    /// Best effort: no `audienceSaved` event, and the Seerr watchlist mirror runs in the background.
    private func tagForCouch(session: UserSession) async {
        guard watchlistEntry == nil, session.couch.isGroup, let details else { return }

        let audience = couchAudience

        guard audience.isNotEmpty else { return }

        let entry = updatedEntry(audience: audience, details: details, session: session)

        do {
            try await watchlistStore.upsert(entry, sessions: session.householdSessions())

            watchlistEntry = watchlistStore.entry(id: entry.id) ?? entry

            mirrorSeerrWatchlists(adding: audience, removing: [], title: details.title)
        } catch {
            logger.warning(
                "Failed to tag a request for the couch",
                metadata: ["error": .string(error.localizedDescription)]
            )
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
            let entry = updatedEntry(audience: audience, details: details, session: session)

            try await watchlistStore.upsert(entry, sessions: session.householdSessions())

            watchlistEntry = watchlistStore.entry(id: entry.id) ?? entry
            events.send(
                .audienceSaved(
                    offerRequest: status == .notRequested && !isLookingUpLibraryItem && requestGate == .allowed
                )
            )

            // Not awaited: the "Who's it for?" spinner stops after the Jellyfin save.
            mirrorSeerrWatchlists(
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
            let title = details?.title ?? watchlistEntry?.title

            try await watchlistStore.remove(entryID: entryID, sessions: session.householdSessions())

            watchlistEntry = nil
            events.send(.audienceRemoved)

            // Not awaited: the "Who's it for?" spinner stops after the Jellyfin save.
            mirrorSeerrWatchlists(adding: [], removing: previousAudience, title: title)
        } catch {
            logger.error(
                "Failed to remove the watchlist entry",
                metadata: ["error": .string(error.localizedDescription)]
            )
            events.send(.failed(error.localizedDescription))
        }
    }

    /// Best effort, in the background: mirrors the audience into each member's own Seerr watchlist
    /// (`SeerrService.syncWatchlists`), after any earlier mirror from this screen finished.
    private func mirrorSeerrWatchlists(
        adding: Set<String>,
        removing: Set<String>,
        title: String?
    ) {
        guard adding.isNotEmpty || removing.isNotEmpty else { return }

        let previousTask = watchlistSyncTask
        let service = seerrService
        let tmdbID = tmdbID
        let mediaType = mediaType

        watchlistSyncTask = Task { @MainActor in
            await previousTask?.value

            await service.syncWatchlists(
                tmdbID: tmdbID,
                mediaType: mediaType,
                title: title,
                adding: adding,
                removing: removing
            )
        }
    }

    /// The entry for this title with `audience`, refreshed from `details`: the existing entry,
    /// else a new one added by a grown-up on the couch. Shared by saving the audience and tagging a request.
    private func updatedEntry(
        audience: Set<String>,
        details: SeerrMediaDetails,
        session: UserSession
    ) -> AudienceWatchlistEntry {
        var entry = watchlistEntry ?? makeEntry(
            details: details,
            audience: audience,
            addedBy: AudienceWatchlistActions.addedByUserID(for: session.couch),
            jellyfinItemID: libraryItem?.id
        )
        entry.audience = audience
        entry.title = details.title
        entry.year = Self.releaseYear(from: details.releaseDate) ?? entry.year
        entry.posterPath = details.posterPath ?? entry.posterPath
        entry.jellyfinItemID = libraryItem?.id ?? entry.jellyfinItemID
        entry.isDeleted = false

        return entry
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
