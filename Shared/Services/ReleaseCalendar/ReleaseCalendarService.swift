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

extension Container {

    var releaseCalendarService: Factory<ReleaseCalendarService> {
        self { @MainActor in ReleaseCalendarService() }
            .singleton
    }
}

enum ReleaseCalendarError: LocalizedError {

    case seerrUnreachable

    var errorDescription: String? {
        switch self {
        case .seerrUnreachable:
            L10n.ReleaseCalendar.seerrUnreachable
        }
    }
}

/// What's coming up in the next `ReleaseCalendarBuilder.daysAhead` days, for the current person.
///
/// - Jellyfin: upcoming episodes of the shows in the library (`GET /Shows/Upcoming`).
/// - Seerr: requested and watchlisted titles that aren't in the library yet, with their
///   release dates from Seerr's TMDB details. Lookups are capped and cached.
///
/// Shared by the "Coming up" screen, its Discover card and the iPhone calendar sync.
@MainActor
final class ReleaseCalendarService: ObservableObject {

    /// Sorted by date, then title.
    @Published
    private(set) var entries: [CalendarEntry] = []
    @Published
    private(set) var isLoading: Bool = false
    /// Set when nothing could be loaded at all.
    @Published
    private(set) var error: Error?
    @Published
    private(set) var lastLoadDate: Date?

    /// Whether the last load reached both Jellyfin and Seerr (when connected),
    /// so a missing entry really means it's gone. The calendar sync only applies complete loads.
    private(set) var lastLoadWasComplete: Bool = false

    private let logger = Logger.swiftfin()

    /// `serverID-userID` the entries belong to.
    private var loadedSessionKey: String?
    private var loadTask: Task<Void, Never>?

    /// Seerr release lookups by `ReleaseCalendarCandidate.key`, for `loadedSessionKey`'s server.
    private var releaseCache: [String: CachedRelease] = [:]
    /// Some Seerr titles couldn't be read during the current load.
    private var isSeerrIncomplete: Bool = false

    /// Entries younger than this are reused unless a refresh is forced.
    private static let freshness: TimeInterval = 15 * 60
    private static let releaseCacheLifetime: TimeInterval = 6 * 60 * 60
    private static let maxUpcomingEpisodes = 300
    private static let maxSeerrRequests = 50
    /// At most this many Seerr titles are looked up per load.
    private static let maxSeerrLookups = 40
    private static let seerrConcurrency = 6

    private struct CachedRelease {
        let details: SeerrReleaseDetails
        let season: SeerrReleaseSeason?
        let fetchedAt: Date
    }

    private struct FetchedRelease: Sendable {
        let key: String
        let details: SeerrReleaseDetails
        let season: SeerrReleaseSeason?
    }

    init() {}

    // MARK: - Loading

    /// Loads the entries unless they are fresh. Concurrent calls share one load.
    func refresh(force: Bool = false) async {
        guard let session = Container.shared.currentUserSession() else {
            entries = []
            loadedSessionKey = nil
            return
        }

        let sessionKey = "\(session.server.id)-\(session.user.id)"

        if loadedSessionKey != sessionKey {
            if loadedSessionKey?.hasPrefix("\(session.server.id)-") != true {
                releaseCache = [:]
            }
            entries = []
            lastLoadDate = nil
            lastLoadWasComplete = false
            loadedSessionKey = sessionKey
        }

        if let loadTask {
            await loadTask.value
            return
        }

        if !force, let lastLoadDate, Date.now.timeIntervalSince(lastLoadDate) < Self.freshness {
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }

            await self.load(session: session, sessionKey: sessionKey, force: force)
        }
        loadTask = task
        isLoading = true

        await task.value

        loadTask = nil
        isLoading = false
    }

    private func load(session: UserSession, sessionKey: String, force: Bool) async {
        let window = ReleaseCalendarBuilder.window()

        var loaded: [CalendarEntry] = []
        var failures: [Error] = []

        isSeerrIncomplete = false

        do {
            loaded += try await jellyfinEntries(session: session, window: window)
        } catch {
            logger.error(
                "Coming up: upcoming episodes failed",
                metadata: ["error": .string(error.localizedDescription)]
            )
            failures.append(error)
        }

        do {
            loaded += try await seerrEntries(window: window, force: force)
        } catch {
            logger.error(
                "Coming up: Seerr release dates failed",
                metadata: ["error": .string(error.localizedDescription)]
            )
            failures.append(error)
        }

        // The person changed while loading
        guard loadedSessionKey == sessionKey else { return }

        if loaded.isEmpty, let failure = failures.first, failures.count == 2 {
            error = failure
            lastLoadWasComplete = false
            return
        }

        // Jellyfin entries come first, so they win any duplicate id
        var seenIDs = Set<String>()
        entries = loaded
            .filter { seenIDs.insert($0.id).inserted }
            .sorted { lhs, rhs in
                lhs.date == rhs.date ? lhs.title < rhs.title : lhs.date < rhs.date
            }
        error = nil
        lastLoadDate = .now
        lastLoadWasComplete = failures.isEmpty && !isSeerrIncomplete
    }

    // MARK: - Jellyfin

    private func jellyfinEntries(session: UserSession, window: DateInterval) async throws -> [CalendarEntry] {
        var parameters = Paths.GetUpcomingEpisodesParameters()
        parameters.userID = session.user.id
        parameters.limit = Self.maxUpcomingEpisodes
        parameters.enableImages = true
        parameters.imageTypeLimit = 1
        parameters.enableImageTypes = [.primary]
        parameters.enableUserData = false

        let request = Paths.getUpcomingEpisodes(parameters: parameters)
        let response = try await session.client.send(request)

        return ReleaseCalendarBuilder.jellyfinEntries(
            from: response.value.items ?? [],
            client: session.client,
            window: window
        )
    }

    // MARK: - Seerr

    private func seerrEntries(window: DateInterval, force: Bool) async throws -> [CalendarEntry] {
        let seerrService = Container.shared.seerrService()

        guard let client = seerrService.client else { return [] }

        let candidates = await seerrCandidates(client: client)

        guard candidates.isNotEmpty else { return [] }

        let now = Date.now
        let pending = candidates.filter { candidate in
            guard !force, let cached = releaseCache[candidate.key] else { return true }

            return now.timeIntervalSince(cached.fetchedAt) > Self.releaseCacheLifetime
        }

        var index = 0
        var failureCount = 0

        while index < pending.count {
            let chunk = Array(pending[index ..< min(index + Self.seerrConcurrency, pending.count)])
            index += Self.seerrConcurrency

            let results = await withTaskGroup(of: FetchedRelease?.self) { group in
                for candidate in chunk {
                    group.addTask {
                        await Self.fetchRelease(candidate: candidate, client: client)
                    }
                }

                var results: [FetchedRelease?] = []
                for await result in group {
                    results.append(result)
                }
                return results
            }

            for result in results {
                guard let result else {
                    failureCount += 1
                    continue
                }

                releaseCache[result.key] = CachedRelease(
                    details: result.details,
                    season: result.season,
                    fetchedAt: .now
                )
            }
        }

        let missingCount = candidates.count(where: { releaseCache[$0.key] == nil })

        // Every lookup failed: Seerr is probably unreachable
        if failureCount > 0, missingCount == candidates.count {
            throw ReleaseCalendarError.seerrUnreachable
        }

        if missingCount > 0 {
            isSeerrIncomplete = true
        }

        return candidates.compactMap { candidate in
            guard let cached = releaseCache[candidate.key] else { return nil }

            return ReleaseCalendarBuilder.seerrEntry(
                candidate: candidate,
                details: cached.details,
                season: cached.season,
                window: window
            )
        }
    }

    /// Requested titles first, then the household watchlists, without the ones already in the library.
    private func seerrCandidates(client: SeerrClient) async -> [ReleaseCalendarCandidate] {
        var candidates: [ReleaseCalendarCandidate] = []
        var seenKeys = Set<String>()

        func add(_ candidate: ReleaseCalendarCandidate) {
            guard seenKeys.insert(candidate.key).inserted else { return }

            candidates.append(candidate)
        }

        do {
            let requests = try await client.requests(take: Self.maxSeerrRequests)

            for request in requests {
                guard request.status != .declined, request.status != .failed,
                      let media = request.media, media.status.isAvailable == false,
                      let tmdbID = media.tmdbId,
                      let mediaType = request.type
                else { continue }

                add(
                    ReleaseCalendarCandidate(
                        mediaType: mediaType,
                        tmdbID: tmdbID,
                        title: nil,
                        posterPath: nil,
                        status: .requested(by: request.requestedBy?.displayName)
                    )
                )
            }
        } catch {
            isSeerrIncomplete = true
            logger.warning(
                "Coming up: Seerr requests failed",
                metadata: ["error": .string(error.localizedDescription)]
            )
        }

        let watchlistStore = Container.shared.audienceWatchlistStore()

        if watchlistStore.lastRefreshDate == nil {
            await watchlistStore.refreshFromCurrentSession()
        }

        for entry in watchlistStore.entries {
            guard entry.jellyfinItemID == nil, let tmdbID = entry.tmdbID else { continue }

            add(
                ReleaseCalendarCandidate(
                    mediaType: entry.kind == .movie ? .movie : .tv,
                    tmdbID: tmdbID,
                    title: entry.title,
                    posterPath: entry.posterPath,
                    status: .onWatchlist
                )
            )
        }

        return Array(candidates.prefix(Self.maxSeerrLookups))
    }

    /// The details, plus the season's episodes when a season starts (to spot a whole season dropping).
    private nonisolated static func fetchRelease(
        candidate: ReleaseCalendarCandidate,
        client: SeerrClient
    ) async -> FetchedRelease? {
        do {
            let details = try await client.releaseDetails(mediaType: candidate.mediaType, tmdbID: candidate.tmdbID)
            var season: SeerrReleaseSeason?

            if candidate.mediaType == .tv,
               let next = details.nextEpisodeToAir, next.episodeNumber == 1,
               let seasonNumber = next.seasonNumber
            {
                season = try? await client.releaseSeason(tmdbID: candidate.tmdbID, seasonNumber: seasonNumber)
            }

            return FetchedRelease(key: candidate.key, details: details, season: season)
        } catch {
            return nil
        }
    }
}
