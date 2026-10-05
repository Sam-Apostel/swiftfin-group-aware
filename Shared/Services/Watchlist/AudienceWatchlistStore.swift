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
import Get
import JellyfinAPI
import Logging

extension Container {

    var audienceWatchlistStore: Factory<AudienceWatchlistStore> {
        self { @MainActor in AudienceWatchlistStore() }
            .singleton
    }
}

enum AudienceWatchlistError: LocalizedError {

    case noAccessibleAccount
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .noAccessibleAccount:
            L10n.Watchlist.noAccessibleAccount
        case .saveFailed:
            L10n.Watchlist.saveFailed
        }
    }
}

/// Household watchlist of "we want to watch X, and it's for these people".
///
/// The source of truth is the Jellyfin DisplayPreferences (`swiftfin-couch-watchlist`, client `swiftfin-couch`)
/// of every account passed in: one `sgw.w.<entry.id>` key per entry, merged by id, newest `updatedAt` wins.
/// Writes are read-modify-write per account (POST replaces the whole map), serialized inside this store.
/// The merged list is cached per server in the app suite, so the UI renders instantly while refreshing.
///
/// Pass the household's sessions (every stored user on this server with a token, current user first)
/// to `refresh`, `upsert` and `remove`. The first session is the "writer" that keeps removal tombstones.
@MainActor
final class AudienceWatchlistStore: ObservableObject {

    /// Non-deleted entries, newest first.
    @Published
    private(set) var entries: [AudienceWatchlistEntry] = []
    @Published
    private(set) var isRefreshing: Bool = false
    @Published
    private(set) var lastRefreshDate: Date?

    /// Every known entry by id, tombstones included.
    private var allEntries: [String: AudienceWatchlistEntry] = [:]
    private var serverID: String?

    private var refreshTask: Task<Void, Never>?
    private var writeChain: Task<Void, Never>?
    /// Bumped by every local change, so a refresh can tell that a write landed while it was fetching.
    private var writeGeneration = 0

    private var tmdbIndexes: [String: TMDBIndex] = [:]

    private let logger = Logger.swiftfin()

    private static let tmdbIndexLifetime: TimeInterval = 10 * 60
    private nonisolated static let itemChunkSize = 50

    init() {}

    // MARK: - Queries

    func entry(id: String) -> AudienceWatchlistEntry? {
        guard let entry = allEntries[id], entry.isDeleted == false else { return nil }

        return entry
    }

    /// Entries whose audience is exactly `memberIDs` (e.g. "Picked for this couch").
    func entries(forExactAudience memberIDs: Set<String>) -> [AudienceWatchlistEntry] {
        entries.filter { $0.isForExactAudience(memberIDs) }
    }

    /// Entries whose audience includes `userID`.
    func entries(including userID: String) -> [AudienceWatchlistEntry] {
        entries.filter { $0.includes(userID) }
    }

    // MARK: - Refresh

    /// Reads the watchlist of every account in `sessions` and merges them.
    ///
    /// Never throws: failures are logged and the last known list is kept.
    /// A refresh that is already running is awaited instead of starting a second one.
    func refresh(sessions: [UserSession]) async {
        let accounts = accessibleAccounts(from: sessions)

        guard let first = accounts.first else {
            logger.warning("Watchlist refresh skipped: no session with an access token")
            return
        }

        activateServer(id: first.serverID)

        if let refreshTask {
            await refreshTask.value
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }

            await self.performRefresh(accounts: accounts)
        }
        refreshTask = task
        isRefreshing = true

        await task.value

        refreshTask = nil
        isRefreshing = false
    }

    /// Convenience for screens that only know the current session:
    /// refreshes from the current session's `householdSessions()`
    /// (the current user plus every other stored user on this server with a token).
    func refreshFromCurrentSession() async {
        guard let session = Container.shared.currentUserSession() else { return }

        await refresh(sessions: session.householdSessions())
    }

    // MARK: - Writes

    /// Adds or updates `entry` (sets `updatedAt`) in the prefs of every audience member and of `entry.addedBy`
    /// that has a session in `sessions`, plus every account that already holds a copy.
    ///
    /// Throws when no account could be written.
    func upsert(_ entry: AudienceWatchlistEntry, sessions: [UserSession]) async throws {
        let accounts = accessibleAccounts(from: sessions)

        guard let first = accounts.first else {
            throw AudienceWatchlistError.noAccessibleAccount
        }

        activateServer(id: first.serverID)

        // Optimistic: show the change right away, the write below confirms it
        let optimistic = AudienceWatchlistSync.prepareUpsert(entry, existing: allEntries[entry.id], now: .now)
        let previous = allEntries[entry.id]
        apply([optimistic])

        do {
            try await serialized { store in
                try await store.performUpsert(entry, accounts: accounts)
            }
        } catch {
            // Roll back the optimistic change unless something newer arrived meanwhile
            if allEntries[entry.id] == optimistic {
                if let previous {
                    allEntries[entry.id] = previous
                } else {
                    allEntries.removeValue(forKey: entry.id)
                }
                publish()
            }
            throw error
        }
    }

    /// Removes the entry from every account in `sessions` that holds it and stores a tombstone
    /// (in those accounts and in the first session's account), so stale copies elsewhere don't resurrect it.
    ///
    /// Throws when no account could be written.
    func remove(entryID: String, sessions: [UserSession]) async throws {
        let accounts = accessibleAccounts(from: sessions)

        guard let first = accounts.first else {
            throw AudienceWatchlistError.noAccessibleAccount
        }

        activateServer(id: first.serverID)

        // Optimistic: hide it right away, the write below confirms it
        let previous = allEntries[entryID]
        let optimistic = previous.map { AudienceWatchlistSync.makeTombstone(of: $0, now: .now) }
        if let optimistic {
            apply([optimistic])
        }

        do {
            try await serialized { store in
                try await store.performRemove(entryID: entryID, accounts: accounts)
            }
        } catch {
            // Roll back the optimistic change unless something newer arrived meanwhile
            if let previous, let optimistic, allEntries[entryID] == optimistic {
                allEntries[entryID] = previous
                publish()
            }
            throw error
        }
    }

    // MARK: - Library items

    /// Resolve entries to library items for display/playback, as seen by `session` (its parental controls apply).
    ///
    /// Uses `jellyfinItemID` when present, else a TMDB id → item map built from all movies and series with a TMDB id,
    /// cached for about 10 minutes per user. Entries not in the library are missing from the result.
    ///
    /// - Returns: `entry.id` → item
    func libraryItems(for entries: [AudienceWatchlistEntry], session: UserSession) async -> [String: BaseItemDto] {
        let liveEntries = entries.filter { $0.isDeleted == false }

        guard liveEntries.isEmpty == false, let account = account(for: session) else { return [:] }

        // Pass 1: entries that know their Jellyfin item id
        var itemIDByEntryID: [String: String] = [:]
        for entry in liveEntries {
            if let itemID = entry.jellyfinItemID, itemID.isEmpty == false {
                itemIDByEntryID[entry.id] = itemID
            }
        }

        var itemsByID = await fetchItems(ids: Array(Set(itemIDByEntryID.values)), account: account)

        // Pass 2: TMDB lookup for entries without a (still existing) Jellyfin item
        let unresolved = liveEntries.filter { entry in
            guard entry.tmdbID != nil else { return false }
            guard let itemID = itemIDByEntryID[entry.id] else { return true }

            return itemsByID[itemID] == nil
        }

        if unresolved.isEmpty == false {
            let index = await tmdbIndex(for: account)
            var missingItemIDs: Set<String> = []

            for entry in unresolved {
                let key = AudienceWatchlistEntry.makeID(tmdbID: entry.tmdbID, kind: entry.kind, jellyfinItemID: nil)
                guard let itemID = index[key] else { continue }

                itemIDByEntryID[entry.id] = itemID
                if itemsByID[itemID] == nil {
                    missingItemIDs.insert(itemID)
                }
            }

            if missingItemIDs.isEmpty == false {
                let more = await fetchItems(ids: Array(missingItemIDs), account: account)
                itemsByID.merge(more) { _, new in new }
            }
        }

        var result: [String: BaseItemDto] = [:]
        for (entryID, itemID) in itemIDByEntryID {
            if let item = itemsByID[itemID] {
                result[entryID] = item
            }
        }
        return result
    }
}

// MARK: - Accounts

extension AudienceWatchlistStore {

    /// What a network call needs from a `UserSession`, safe to pass to child tasks.
    struct Account: Sendable {
        let userID: String
        let serverID: String
        let client: JellyfinClient
    }

    struct TMDBIndex {
        let date: Date
        let itemIDByEntryID: [String: String]
    }

    /// `nil` when the user has no token (touching the primary's `client` would hit `UserState.accessToken`'s assertion).
    private func account(for session: UserSession) -> Account? {
        guard session.user.storedAccessToken != nil else { return nil }

        return Account(userID: session.user.id, serverID: session.server.id, client: session.client)
    }

    /// One account per user, on the first session's server, in the order passed in.
    private func accessibleAccounts(from sessions: [UserSession]) -> [Account] {
        guard let serverID = sessions.first?.server.id else { return [] }

        var seenUserIDs: Set<String> = []
        var accounts: [Account] = []

        for session in sessions where session.server.id == serverID {
            guard seenUserIDs.insert(session.user.id).inserted else { continue }
            guard let account = account(for: session) else {
                logger.warning("Watchlist: skipping user \(session.user.username), no access token on this device")
                continue
            }

            accounts.append(account)
        }

        return accounts
    }
}

// MARK: - State

extension AudienceWatchlistStore {

    private static func cacheKey(serverID: String) -> String {
        "sgw.watchlist.cache.\(serverID)"
    }

    /// Switches to `id`'s watchlist, loading its cached copy when the server changes.
    private func activateServer(id: String) {
        guard serverID != id else { return }

        serverID = id
        tmdbIndexes = [:]
        allEntries = [:]

        if let data = UserDefaults.appSuite.data(forKey: Self.cacheKey(serverID: id)),
           let cached = try? AudienceWatchlistSync.makeDecoder().decode([AudienceWatchlistEntry].self, from: data)
        {
            allEntries = Dictionary(cached.map { ($0.id, $0) }) { lhs, rhs in
                AudienceWatchlistSync.newest(lhs, rhs)
            }
        }

        publish()
    }

    /// Merges `changed` into the local state (newest wins) and publishes.
    private func apply(_ changed: [AudienceWatchlistEntry]) {
        writeGeneration += 1
        for entry in changed {
            allEntries[entry.id] = AudienceWatchlistSync.newest(allEntries[entry.id], entry)
        }
        publish()
        saveCache()
    }

    private func publish() {
        let visible = AudienceWatchlistSync.visibleEntries(allEntries)
        if visible != entries {
            entries = visible
        }
    }

    private func saveCache() {
        guard let serverID else { return }

        let values = Array(allEntries.values)
        guard let data = try? AudienceWatchlistSync.makeEncoder().encode(values) else { return }

        UserDefaults.appSuite.set(data, forKey: Self.cacheKey(serverID: serverID))
    }

    /// Runs writes one at a time, so two read-modify-writes never interleave.
    private func serialized(
        _ operation: @escaping @Sendable @MainActor (AudienceWatchlistStore) async throws -> Void
    ) async throws {
        let previous = writeChain

        let task = Task { @MainActor [weak self] in
            await previous?.value
            guard let self else { return }

            try await operation(self)
        }

        writeChain = Task { @MainActor in
            _ = await task.result
        }

        try await task.value
    }
}

// MARK: - Sync

extension AudienceWatchlistStore {

    struct Fetched: Sendable {
        let account: Account
        let customPrefs: [String: String?]?
        let error: Error?
    }

    struct Write: Sendable {
        let account: Account
        let customPrefs: [String: String]
    }

    private func performRefresh(accounts: [Account]) async {
        let startGeneration = writeGeneration
        let fetched = await Self.fetchAll(accounts)
        let reachable = logFailures(fetched)

        // Also bail when the server changed while fetching
        guard reachable.isEmpty == false, serverID == accounts.first?.serverID else { return }

        let remote = AudienceWatchlistSync.merge(reachable.map { AudienceWatchlistSync.entries(in: $0.customPrefs ?? [:]) })

        if reachable.count == fetched.count, writeGeneration == startGeneration {
            // Complete picture: the server state replaces ours (drops entries whose tombstones were pruned)
            allEntries = remote
        } else {
            // Partial, or a local write landed while fetching (the fetched prefs may predate it):
            // keep what we know, newest wins
            allEntries = AudienceWatchlistSync.merge([allEntries, remote])
        }

        lastRefreshDate = .now
        publish()
        saveCache()

        // Some accounts hold stale copies (e.g. a removal made on a device without their token): fix them in the background
        let needsHealing = reachable.contains { fetched in
            let stored = AudienceWatchlistSync.entries(in: fetched.customPrefs ?? [:])
            return AudienceWatchlistSync.healingChanges(stored: stored, merged: remote).isEmpty == false
        }

        if needsHealing {
            Task { @MainActor [weak self] in
                guard let self else { return }

                do {
                    try await self.serialized { store in
                        try await store.performHealing(accounts: accounts)
                    }
                } catch {
                    self.logger.error("Watchlist: updating stale copies failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func performHealing(accounts: [Account]) async throws {
        let fetched = await Self.fetchAll(accounts)
        let reachable = logFailures(fetched)
        let remote = AudienceWatchlistSync.merge(reachable.map { AudienceWatchlistSync.entries(in: $0.customPrefs ?? [:]) })
        let now = Date.now

        let writes: [Write] = reachable.compactMap { fetched in
            let customPrefs = fetched.customPrefs ?? [:]
            let changes = AudienceWatchlistSync.healingChanges(
                stored: AudienceWatchlistSync.entries(in: customPrefs),
                merged: remote
            )
            guard changes.isEmpty == false else { return nil }

            return Write(
                account: fetched.account,
                customPrefs: AudienceWatchlistSync.customPrefsForWriting(existing: customPrefs, changes: changes, now: now)
            )
        }

        guard writes.isEmpty == false else { return }

        logger.info("Watchlist: updating stale copies in \(writes.count) account(s)")
        try await post(writes)
    }

    /// A write of `change` to one account, which also replaces that account's stale copies with the `merged` winners.
    private static func makeWrite(
        _ fetched: Fetched,
        change: AudienceWatchlistEntry,
        merged: [String: AudienceWatchlistEntry],
        now: Date
    ) -> Write {
        let customPrefs = fetched.customPrefs ?? [:]

        var changes = AudienceWatchlistSync.healingChanges(
            stored: AudienceWatchlistSync.entries(in: customPrefs),
            merged: merged
        )
        changes[change.id] = change

        return Write(
            account: fetched.account,
            customPrefs: AudienceWatchlistSync.customPrefsForWriting(existing: customPrefs, changes: changes, now: now)
        )
    }

    private func performUpsert(_ entry: AudienceWatchlistEntry, accounts: [Account]) async throws {
        let fetched = await Self.fetchAll(accounts)
        let reachable = logFailures(fetched)

        guard reachable.isEmpty == false else {
            throw fetched.compactMap(\.error).first ?? (AudienceWatchlistError.saveFailed as Error)
        }

        let remote = AudienceWatchlistSync.merge(reachable.map { AudienceWatchlistSync.entries(in: $0.customPrefs ?? [:]) })
        let now = Date.now

        // The optimistic local copy is ignored here: it would make the stored copy look older than it is
        let existing = remote[entry.id]
        let prepared = AudienceWatchlistSync.prepareUpsert(entry, existing: existing, now: now)
        let key = AudienceWatchlistSync.key(forEntryID: prepared.id)
        let targets = prepared.audience.union([prepared.addedBy])

        var writes: [Write] = []

        for fetched in reachable {
            let customPrefs = fetched.customPrefs ?? [:]
            guard targets.contains(fetched.account.userID) || customPrefs[key] != nil else { continue }

            writes.append(Self.makeWrite(fetched, change: prepared, merged: remote, now: now))
        }

        // Nobody in the audience is reachable from this device: keep it in the writer's account
        if writes.isEmpty, let writer = reachable.first {
            writes.append(Self.makeWrite(writer, change: prepared, merged: remote, now: now))
        }

        let missing = targets.subtracting(accounts.map(\.userID))
        if missing.isEmpty == false {
            logger.info("Watchlist: \(missing.count) audience member(s) have no session on this device, their copy is skipped")
        }

        try await post(writes)

        // The user switched servers while this was saving: don't mix it into the other server's list
        guard serverID == accounts.first?.serverID else { return }

        writeGeneration += 1
        allEntries = AudienceWatchlistSync.merge([allEntries, remote])
        allEntries[prepared.id] = prepared
        publish()
        saveCache()
    }

    private func performRemove(entryID: String, accounts: [Account]) async throws {
        let fetched = await Self.fetchAll(accounts)
        let reachable = logFailures(fetched)

        guard reachable.isEmpty == false else {
            throw fetched.compactMap(\.error).first ?? (AudienceWatchlistError.saveFailed as Error)
        }

        let remote = AudienceWatchlistSync.merge(reachable.map { AudienceWatchlistSync.entries(in: $0.customPrefs ?? [:]) })
        let now = Date.now

        // Prefer the stored copy; fall back to the local one (only used to fill the tombstone's fields)
        let existing = remote[entryID] ?? allEntries[entryID]

        guard let existing else {
            guard serverID == accounts.first?.serverID else { return }

            allEntries.removeValue(forKey: entryID)
            publish()
            saveCache()
            return
        }

        let tombstone = AudienceWatchlistSync.makeTombstone(of: existing, now: now)
        let key = AudienceWatchlistSync.key(forEntryID: entryID)
        let writerID = accounts.first?.userID

        var writes: [Write] = []

        for fetched in reachable {
            let customPrefs = fetched.customPrefs ?? [:]
            guard fetched.account.userID == writerID || customPrefs[key] != nil else { continue }

            writes.append(Self.makeWrite(fetched, change: tombstone, merged: remote, now: now))
        }

        if writes.isEmpty == false {
            try await post(writes)
        }

        guard serverID == accounts.first?.serverID else { return }

        writeGeneration += 1
        allEntries = AudienceWatchlistSync.merge([allEntries, remote])
        allEntries[entryID] = tombstone
        publish()
        saveCache()
    }

    /// Successful fetches; failures are logged.
    private func logFailures(_ fetched: [Fetched]) -> [Fetched] {
        for failure in fetched where failure.customPrefs == nil {
            logger.error(
                "Watchlist: reading prefs of user \(failure.account.userID) failed: \(failure.error?.localizedDescription ?? "unknown error")"
            )
        }
        return fetched.filter { $0.customPrefs != nil }
    }

    /// POSTs every write; throws only when all of them failed.
    private func post(_ writes: [Write]) async throws {
        let errors = await Self.postAll(writes)

        for error in errors {
            logger.error("Watchlist: saving prefs failed: \(error.localizedDescription)")
        }

        if let first = errors.first, errors.count == writes.count {
            throw first
        }
    }

    // MARK: Network (nonisolated, runs in parallel)

    private nonisolated static func fetchAll(_ accounts: [Account]) async -> [Fetched] {
        await withTaskGroup(of: (Int, Fetched).self) { group in
            for (offset, account) in accounts.enumerated() {
                group.addTask {
                    do {
                        let customPrefs = try await Self.fetchCustomPrefs(account: account)
                        return (offset, Fetched(account: account, customPrefs: customPrefs, error: nil))
                    } catch {
                        return (offset, Fetched(account: account, customPrefs: nil, error: error))
                    }
                }
            }

            var results: [(Int, Fetched)] = []
            for await result in group {
                results.append(result)
            }
            // Keep the order of `accounts`: the first one is the writer
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    /// GET with our own lenient DTO: the SDK's `DisplayPreferencesDto` fails on a fresh row's `"tvhome": null`.
    private nonisolated static func fetchCustomPrefs(account: Account) async throws -> [String: String?] {
        let request = Request<CouchPrefsDTO>(
            path: "/DisplayPreferences/\(AudienceWatchlistSync.displayPreferencesID)",
            query: [
                ("userId", account.userID),
                ("client", AudienceWatchlistSync.client),
            ]
        )

        let response = try await account.client.send(request)
        return response.value.customPrefs
    }

    /// - Returns: the errors of the failed writes
    private nonisolated static func postAll(_ writes: [Write]) async -> [Error] {
        await withTaskGroup(of: Error?.self) { group in
            for write in writes {
                group.addTask {
                    do {
                        try await Self.postCustomPrefs(write.customPrefs, account: write.account)
                        return nil
                    } catch {
                        return error
                    }
                }
            }

            var errors: [Error] = []
            for await error in group {
                if let error {
                    errors.append(error)
                }
            }
            return errors
        }
    }

    /// POST replaces the whole map, so `customPrefs` must be the complete set of our keys.
    /// The other fields are the server defaults, sent explicitly because the body is a full DTO.
    private nonisolated static func postCustomPrefs(_ customPrefs: [String: String], account: Account) async throws {
        let body = DisplayPreferencesDto(
            client: AudienceWatchlistSync.client,
            customPrefs: customPrefs,
            id: AudienceWatchlistSync.displayPreferencesID,
            isRememberIndexing: false,
            isRememberSorting: false,
            isShowBackdrop: true,
            isShowSidebar: false,
            primaryImageHeight: 250,
            primaryImageWidth: 250,
            scrollDirection: .horizontal,
            sortBy: "SortName",
            sortOrder: .ascending
        )

        let request = Paths.updateDisplayPreferences(
            displayPreferencesID: AudienceWatchlistSync.displayPreferencesID,
            userID: account.userID,
            client: AudienceWatchlistSync.client,
            body
        )

        try await account.client.send(request)
    }
}

// MARK: - Library lookups

extension AudienceWatchlistStore {

    private func tmdbIndex(for account: Account) async -> [String: String] {
        let key = "\(account.serverID)|\(account.userID)"

        if let cached = tmdbIndexes[key], Date.now.timeIntervalSince(cached.date) < Self.tmdbIndexLifetime {
            return cached.itemIDByEntryID
        }

        do {
            let index = try await Self.fetchTMDBIndex(account: account)
            tmdbIndexes[key] = TMDBIndex(date: .now, itemIDByEntryID: index)
            return index
        } catch {
            logger.error("Watchlist: building the TMDB index failed: \(error.localizedDescription)")
            return tmdbIndexes[key]?.itemIDByEntryID ?? [:]
        }
    }

    private func fetchItems(ids: [String], account: Account) async -> [String: BaseItemDto] {
        guard ids.isEmpty == false else { return [:] }

        do {
            return try await Self.requestItems(ids: ids, account: account)
        } catch {
            logger.error("Watchlist: fetching library items failed: \(error.localizedDescription)")
            return [:]
        }
    }

    /// `"tmdb-movie-862"`-style key → Jellyfin item id, for every movie and series with a TMDB id.
    private nonisolated static func fetchTMDBIndex(account: Account) async throws -> [String: String] {
        var parameters = Paths.GetItemsParameters()
        parameters.userID = account.userID
        parameters.hasTmdbID = true
        parameters.fields = [.providerIDs]
        parameters.includeItemTypes = [.movie, .series]
        parameters.isRecursive = true
        parameters.enableImages = false
        parameters.enableUserData = false

        let response = try await account.client.send(Paths.getItems(parameters: parameters))

        var index: [String: String] = [:]

        for item in response.value.items ?? [] {
            guard let itemID = item.id,
                  let kind = AudienceWatchlistEntry.mediaKind(of: item.type),
                  let tmdbID = AudienceWatchlistEntry.tmdbID(of: item) else { continue }

            let key = AudienceWatchlistEntry.makeID(tmdbID: tmdbID, kind: kind, jellyfinItemID: nil)
            if index[key] == nil {
                index[key] = itemID
            }
        }

        return index
    }

    /// Full items (images, user data, poster fields) by id, in chunks to keep the URL short.
    private nonisolated static func requestItems(ids: [String], account: Account) async throws -> [String: BaseItemDto] {
        var result: [String: BaseItemDto] = [:]
        var start = 0

        while start < ids.count {
            let chunk = Array(ids[start ..< min(start + Self.itemChunkSize, ids.count)])
            start += Self.itemChunkSize

            var parameters = Paths.GetItemsParameters()
            parameters.userID = account.userID
            parameters.ids = chunk
            parameters.fields = PosterSubtitleField.itemFields + [.providerIDs, .overview]
            parameters.enableUserData = true

            let response = try await account.client.send(Paths.getItems(parameters: parameters))

            for item in response.value.items ?? [] {
                if let id = item.id {
                    result[id] = item
                }
            }
        }

        return result
    }
}
