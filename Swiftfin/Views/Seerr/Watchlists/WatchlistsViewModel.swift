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
import UIKit

/// Drives `WatchlistsView`: groups the household's audience-tagged watchlist by audience,
/// and resolves each entry's availability (Jellyfin library first, then Seerr).
@MainActor
final class WatchlistsViewModel: ViewModel {

    // MARK: - Published

    @Published
    var filter: WatchlistsFilter = .all {
        didSet { rebuildSections() }
    }

    @Published
    var error: Error?

    /// Grouped + filtered + sorted sections, ready for display
    @Published
    private(set) var sections: [WatchlistsSection] = []

    /// All (unfiltered) entries of the store
    @Published
    private(set) var entries: [AudienceWatchlistEntry] = []

    @Published
    private(set) var isRefreshing: Bool = false

    /// False until the first watchlist refresh finished (or the store already had one)
    @Published
    private(set) var hasLoaded: Bool = false

    /// entry.id → library item, as seen by the current user
    @Published
    private(set) var libraryItems: [String: BaseItemDto] = [:]

    /// entry.id → Seerr status (only for entries not found in the library)
    @Published
    private(set) var seerrStatuses: [String: WatchlistSeerrStatus] = [:]

    /// Every stored user on this server (avatars + names for the audience labels)
    @Published
    private(set) var users: [UserState] = []

    // MARK: - Dependencies

    private let store: AudienceWatchlistStore
    private let seerrService: SeerrService

    private var availabilityTask: Task<Void, Never>?

    /// Seerr lookups are shared across screen instances so re-opening the screen is instant.
    private static var seerrStatusCache: [String: WatchlistSeerrStatus] = [:]
    /// The Jellyfin server the cache belongs to: each server has its own Seerr
    private static var seerrStatusCacheServerID: String?
    private static let seerrStatusTTL: TimeInterval = 10 * 60
    private static let seerrConcurrency = 6

    // MARK: - Init

    override init() {
        self.store = Container.shared.audienceWatchlistStore()
        self.seerrService = Container.shared.seerrService()

        super.init()

        resetSeerrCacheIfServerChanged()
        self.seerrStatuses = Self.seerrStatusCache
        self.entries = store.entries
        self.isRefreshing = store.isRefreshing
        self.hasLoaded = store.lastRefreshDate != nil || store.entries.isNotEmpty

        store.$entries
            .receive(on: DispatchQueue.main)
            .sink { [weak self] entries in
                guard let self else { return }

                self.entries = entries
                self.rebuildSections()
                self.resolveAvailability(force: false)
            }
            .store(in: &cancellables)

        store.$isRefreshing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRefreshing in
                self?.isRefreshing = isRefreshing
            }
            .store(in: &cancellables)

        reloadUsers()
        rebuildSections()
    }

    // MARK: - Session helpers

    private var householdSessions: [UserSession] {
        userSession?.householdSessions() ?? []
    }

    private func reloadUsers() {
        guard let userSession else {
            users = []
            return
        }

        // Every stored user on this server (no keychain access), to name audience members
        let storedUsers = StoredValues[.User.users]
            .filter { $0.serverID == userSession.server.id }

        var seen = Set<String>()
        users = ([userSession.user] + userSession.couch.members + storedUsers)
            .filter { seen.insert($0.id).inserted }
    }

    private func user(id: String) -> UserState? {
        users.first { $0.id == id }
    }

    /// Section header icon: everyone, a kid on their own, one person, a pair, or a bigger group.
    func systemImage(for audience: Set<String>) -> String {
        if users.count > 1, audience == Set(users.map(\.id)) {
            return "person.3.fill"
        }

        switch audience.count {
        case 1:
            if let id = audience.first, user(id: id)?.isKid == true {
                return "figure.child"
            }
            return "person.fill"

        case 2:
            return "heart.fill"

        default:
            return "person.2.fill"
        }
    }

    private func resetSeerrCacheIfServerChanged() {
        let serverID = userSession?.server.id

        guard Self.seerrStatusCacheServerID != serverID else { return }

        Self.seerrStatusCache = [:]
        Self.seerrStatusCacheServerID = serverID
    }

    // MARK: - Refresh

    func onFirstAppear() {
        rebuildSections()
        resolveAvailability(force: false)

        Task {
            await refresh(force: false)
        }
    }

    /// Re-read every household account's watchlist (pull-to-refresh), then re-resolve availability.
    func refresh(force: Bool = true) async {
        reloadUsers()

        let sessions = householdSessions

        guard sessions.isNotEmpty else {
            logger.error("Watchlists: no household sessions to refresh from")
            hasLoaded = true
            return
        }

        if force {
            Self.seerrStatusCache = [:]
        }

        await store.refresh(sessions: sessions)
        hasLoaded = true

        // `store.$entries` triggers a non-forced resolve; force one here so
        // library availability is re-checked even when entries did not change.
        resolveAvailability(force: force)
        await availabilityTask?.value
    }

    // MARK: - Availability

    func availability(for entry: AudienceWatchlistEntry) -> WatchlistAvailability {
        if libraryItems[entry.id] != nil {
            return .inLibrary
        }

        guard let info = seerrStatuses[entry.id] else {
            return .unknown
        }

        switch info.status {
        case .available, .partiallyAvailable:
            return .inLibrary
        case .pending, .processing:
            return .requested
        default:
            return .notRequested
        }
    }

    func libraryItem(for entry: AudienceWatchlistEntry) -> BaseItemDto? {
        libraryItems[entry.id]
    }

    /// The Jellyfin item to open for this entry, if it is in the library
    func jellyfinItemID(for entry: AudienceWatchlistEntry) -> String? {
        libraryItems[entry.id]?.id ?? entry.jellyfinItemID ?? seerrStatuses[entry.id]?.jellyfinItemID
    }

    var isSeerrConfigured: Bool {
        seerrService.isConfigured
    }

    private func resolveAvailability(force: Bool) {
        availabilityTask?.cancel()

        let entries = self.entries

        guard entries.isNotEmpty, let session = userSession else {
            return
        }

        availabilityTask = Task { [weak self] in
            guard let self else { return }

            // 1. Jellyfin library (store caches the TMDB → item map)
            let items = await self.store.libraryItems(for: entries, session: session)

            guard !Task.isCancelled else { return }

            self.libraryItems = items
            self.rebuildSections()

            // 2. Seerr, for everything with a TMDB id that is not in the library
            await self.resolveSeerrStatuses(
                for: entries.filter { items[$0.id] == nil && $0.tmdbID != nil },
                force: force
            )
        }
    }

    private func resolveSeerrStatuses(for entries: [AudienceWatchlistEntry], force: Bool) async {
        guard let client = seerrService.client else { return }

        resetSeerrCacheIfServerChanged()

        let now = Date()
        let pending = entries.filter { entry in
            guard !force, let cached = Self.seerrStatusCache[entry.id] else { return true }

            return now.timeIntervalSince(cached.fetchedAt) > Self.seerrStatusTTL
        }

        guard pending.isNotEmpty else {
            seerrStatuses = Self.seerrStatusCache
            rebuildSections()
            return
        }

        var index = 0

        while index < pending.count {
            guard !Task.isCancelled else { return }

            let chunk = Array(pending[index ..< min(index + Self.seerrConcurrency, pending.count)])
            index += Self.seerrConcurrency

            let results = await withTaskGroup(of: (String, WatchlistSeerrStatus?).self) { group in
                for entry in chunk {
                    guard let tmdbID = entry.tmdbID else { continue }

                    let mediaType: SeerrMediaType = entry.kind == .movie ? .movie : .tv
                    let entryID = entry.id

                    group.addTask {
                        do {
                            let details = try await client.details(mediaType: mediaType, tmdbID: tmdbID)
                            let info = WatchlistSeerrStatus(
                                status: details.mediaInfo?.status ?? .unknown,
                                jellyfinItemID: details.mediaInfo?.jellyfinMediaId,
                                fetchedAt: Date()
                            )
                            return (entryID, info)
                        } catch {
                            return (entryID, nil)
                        }
                    }
                }

                var results: [(String, WatchlistSeerrStatus?)] = []
                for await result in group {
                    results.append(result)
                }
                return results
            }

            for (entryID, info) in results {
                if let info {
                    Self.seerrStatusCache[entryID] = info
                } else {
                    logger.error("Watchlists: Seerr status lookup failed", metadata: ["entry": .string(entryID)])
                }
            }

            guard !Task.isCancelled else { return }

            seerrStatuses = Self.seerrStatusCache
            rebuildSections()
        }
    }

    // MARK: - Sections

    private func rebuildSections() {
        let couchIDs = userSession?.couch.memberIDs ?? []
        let primaryID = userSession?.user.id

        let activeFilter = self.filter
        let filtered = entries.filter { activeFilter.includes(self.availability(for: $0)) }

        // Group, keeping the store's order (newest first) inside each group
        var order: [String] = []
        var grouped: [String: [AudienceWatchlistEntry]] = [:]

        for entry in filtered {
            let id = WatchlistsSection.makeID(audience: entry.audience)
            if grouped[id] == nil {
                order.append(id)
                grouped[id] = []
            }
            grouped[id]?.append(entry)
        }

        let unsorted: [WatchlistsSection] = order.compactMap { id in
            guard let entries = grouped[id], let first = entries.first else { return nil }

            return WatchlistsSection(id: id, audience: first.audience, entries: entries)
        }

        func rank(_ section: WatchlistsSection) -> Int {
            if couchIDs.isNotEmpty, section.audience == couchIDs {
                return 0
            }
            if let primaryID, section.audience.contains(primaryID) {
                return 1
            }
            return 2
        }

        // `order` is newest-first, so a stable sort by rank keeps the newest audiences on top within a rank
        sections = unsorted
            .enumerated()
            .sorted { lhs, rhs in
                let lhsRank = rank(lhs.element)
                let rhsRank = rank(rhs.element)
                return lhsRank == rhsRank ? lhs.offset < rhs.offset : lhsRank < rhsRank
            }
            .map(\.element)
    }

    // MARK: - Mutations

    func remove(_ entry: AudienceWatchlistEntry) async {
        do {
            try await store.remove(entryID: entry.id, sessions: householdSessions)
            UIDevice.feedback(.success)
            syncSeerrWatchlists(for: entry, adding: [], removing: entry.audience)
        } catch {
            logger.error("Watchlists: failed to remove entry", metadata: ["error": .string(error.localizedDescription)])
            // `.errorMessage` plays the error haptic
            self.error = error
        }
    }

    func changeAudience(of entry: AudienceWatchlistEntry, to audience: Set<String>) async {
        guard audience.isNotEmpty else {
            await remove(entry)
            return
        }
        guard audience != entry.audience else { return }

        var updated = entry
        updated.audience = audience

        do {
            try await store.upsert(updated, sessions: householdSessions)
            UIDevice.feedback(.success)
            syncSeerrWatchlists(
                for: entry,
                adding: audience.subtracting(entry.audience),
                removing: entry.audience.subtracting(audience)
            )
        } catch {
            logger.error("Watchlists: failed to update audience", metadata: ["error": .string(error.localizedDescription)])
            // `.errorMessage` plays the error haptic
            self.error = error
        }
    }

    /// Best effort, fire-and-forget: keep each member's own Seerr watchlist in line with the audience.
    ///
    /// By Jellyfin user id (like #14), so members that are not stored on this device are synced too
    /// (through the API key). Members with a Quick Connect session use their own session.
    private func syncSeerrWatchlists(for entry: AudienceWatchlistEntry, adding: Set<String>, removing: Set<String>) {
        guard entry.tmdbID != nil, seerrService.isConfigured else { return }
        guard adding.isNotEmpty || removing.isNotEmpty else { return }

        Task { [seerrService] in
            await seerrService.syncWatchlists(for: entry, adding: adding, removing: removing)
        }
    }
}
