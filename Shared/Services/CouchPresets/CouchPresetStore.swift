//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Defaults
import FactoryKit
import Foundation
import JellyfinAPI
import Logging

extension Container {

    var couchPresetStore: Factory<CouchPresetStore> {
        self { @MainActor in CouchPresetStore() }
            .singleton
    }
}

extension Defaults.Keys.Couch {

    /// The last couches, newest first. Each element is the member ids in pick order, comma-joined.
    ///
    /// Local to this device, used for the "last couches" chips on the picker.
    static let recentMemberIDs = Defaults.Key<[String]>("couchRecentMemberIDs", default: [], suite: .appSuite)

    /// Whether the history was seeded from `lastMemberIDs` once, so forgotten couches don't come back.
    static let hasSeededRecents = Defaults.Key<Bool>("couchHasSeededRecents", default: false, suite: .appSuite)
}

/// Named couches ("Date night", "With Tuur") and the last couches, for the one-tap chips on the picker.
///
/// Named presets are household-wide: they are stored in the Jellyfin DisplayPreferences
/// (`swiftfin-couch-presets`, client `swiftfin-couch`) of **every** stored user on the server that has a token,
/// merged by id, newest `updatedAt` wins. The picker runs signed out, so the store builds inert member sessions
/// from the stored users itself.
///
/// Local first: every change is applied and cached right away (the chips render instantly, also offline),
/// then written to the server. A failed write is retried by the next refresh, which pushes the merged
/// state to every account whose copy differs.
@MainActor
final class CouchPresetStore: ObservableObject {

    /// Visible presets per server id, sorted by name.
    @Published
    private(set) var presetsByServerID: [String: [CouchPreset]] = [:]
    /// The last couches, newest first, as member ids in pick order.
    @Published
    private(set) var recentCouches: [[String]] = []

    /// Every known preset per server id, tombstones included.
    private var allByServerID: [String: [String: CouchPreset]] = [:]

    private var syncChain: Task<Void, Never>?
    private var refreshingServerIDs: Set<String> = []
    private var clients: [String: JellyfinClient] = [:]

    private let logger = Logger.swiftfin()

    private static let cacheKey = "sgw.couchPresets.cache"

    init() {
        loadCache()
        loadRecents()
    }

    // MARK: - Queries

    func presets(serverID: String) -> [CouchPreset] {
        presetsByServerID[serverID] ?? []
    }

    /// The named preset with exactly these members, if any.
    func preset(serverID: String, memberIDs: Set<String>) -> CouchPreset? {
        presets(serverID: serverID).first { $0.memberSet == memberIDs }
    }

    // MARK: - Recent couches

    /// Remembers a couch that just started watching, as the newest of the last couches.
    func recordRecent(memberIDs: [String]) {
        Defaults[.Couch.recentMemberIDs] = CouchPresetSync.recordingRecent(memberIDs, in: Defaults[.Couch.recentMemberIDs])
        loadRecents()
    }

    /// Removes a couch from the last couches.
    func forgetRecent(memberIDs: [String]) {
        Defaults[.Couch.recentMemberIDs] = CouchPresetSync.forgettingRecent(Set(memberIDs), in: Defaults[.Couch.recentMemberIDs])
        loadRecents()
    }

    /// Seeds the history with the last couch picked before presets existed.
    func seedRecentsIfNeeded() {
        guard !Defaults[.Couch.hasSeededRecents] else { return }

        Defaults[.Couch.hasSeededRecents] = true

        let lastMemberIDs = Defaults[.Couch.lastMemberIDs]

        guard Defaults[.Couch.recentMemberIDs].isEmpty, lastMemberIDs.isNotEmpty else { return }

        recordRecent(memberIDs: lastMemberIDs)
    }

    // MARK: - Presets

    /// Saves a new or edited preset for the users of `server`.
    ///
    /// Applied locally right away; the server write happens in the background and never throws.
    func save(_ preset: CouchPreset, server: ServerState, users: [UserState]) {
        var all = allByServerID[server.id] ?? [:]
        var stamped = CouchPresetSync.stamped(preset, existing: all[preset.id], now: .now)
        stamped.isDeleted = false
        all[stamped.id] = stamped

        setAll(all, serverID: server.id)
        sync(server: server, users: users, change: stamped)
    }

    /// Deletes a preset everywhere (a tombstone is kept so stale copies don't bring it back).
    func delete(presetID: String, server: ServerState, users: [UserState]) {
        var all = allByServerID[server.id] ?? [:]

        guard let existing = all[presetID] else { return }

        let tombstone = CouchPresetSync.makeTombstone(of: existing, now: .now)
        all[presetID] = tombstone

        setAll(all, serverID: server.id)
        sync(server: server, users: users, change: tombstone)
    }

    /// Reads the presets of every account on `server` and merges them.
    /// Accounts that hold a stale copy are updated. Never throws; failures are logged.
    func refresh(server: ServerState, users: [UserState]) {
        guard refreshingServerIDs.insert(server.id).inserted else { return }

        sync(server: server, users: users, change: nil) { [weak self] in
            self?.refreshingServerIDs.remove(server.id)
        }
    }
}

// MARK: - State

extension CouchPresetStore {

    private func setAll(_ all: [String: CouchPreset], serverID: String) {
        allByServerID[serverID] = all

        let visible = CouchPresetSync.visiblePresets(all)
        if presetsByServerID[serverID] != visible {
            presetsByServerID[serverID] = visible
        }

        saveCache()
    }

    private func loadRecents() {
        let recents = Defaults[.Couch.recentMemberIDs]
            .map(CouchPresetSync.recentMemberIDs(from:))
            .filter(\.isNotEmpty)

        if recents != recentCouches {
            recentCouches = recents
        }
    }

    private func loadCache() {
        guard let data = UserDefaults.appSuite.data(forKey: Self.cacheKey),
              let cached = try? AudienceWatchlistSync.makeDecoder().decode([String: [CouchPreset]].self, from: data)
        else { return }

        for (serverID, presets) in cached {
            let all = Dictionary(presets.map { ($0.id, $0) }) { lhs, rhs in
                CouchPresetSync.newest(lhs, rhs)
            }
            allByServerID[serverID] = all
            presetsByServerID[serverID] = CouchPresetSync.visiblePresets(all)
        }
    }

    private func saveCache() {
        let values = allByServerID.mapValues { Array($0.values) }

        guard let data = try? AudienceWatchlistSync.makeEncoder().encode(values) else { return }

        UserDefaults.appSuite.set(data, forKey: Self.cacheKey)
    }
}

// MARK: - Sync

extension CouchPresetStore {

    /// What a network call needs from a stored user, safe to pass to child tasks.
    struct Account: Sendable {
        let userID: String
        let client: JellyfinClient
    }

    struct Fetched: Sendable {
        let account: Account
        let customPrefs: [String: String?]?
        let error: Error?
    }

    /// An inert client for every user of `server` with a stored token.
    ///
    /// Uses the per-member device id of couch member sessions, so these calls never take over anyone's server session.
    private func makeAccounts(server: ServerState, users: [UserState]) -> [Account] {
        var seenUserIDs: Set<String> = []
        var accounts: [Account] = []

        for user in users where user.serverID == server.id {
            guard seenUserIDs.insert(user.id).inserted else { continue }
            guard let token = user.storedAccessToken else { continue }

            let cacheKey = "\(server.id)|\(server.effectiveServerURL.absoluteString)|\(user.id)|\(token)"
            let client: JellyfinClient

            if let cached = clients[cacheKey] {
                client = cached
            } else {
                client = UserSession(
                    server: server,
                    user: user,
                    couch: nil,
                    isCouchMember: true
                ).client
                clients[cacheKey] = client
            }

            accounts.append(Account(userID: user.id, client: client))
        }

        return accounts
    }

    /// Runs syncs one at a time, so two read-modify-writes never interleave.
    private func sync(
        server: ServerState,
        users: [UserState],
        change: CouchPreset?,
        completion: (@MainActor () -> Void)? = nil
    ) {
        let accounts = makeAccounts(server: server, users: users)
        let serverID = server.id
        let previous = syncChain

        syncChain = Task { @MainActor [weak self] in
            await previous?.value

            if let self {
                if accounts.isEmpty {
                    self.logger.warning("Couch presets: no user with an access token on this server, kept on this device only")
                } else {
                    await self.performSync(serverID: serverID, accounts: accounts, change: change)
                }
            }

            completion?()
        }
    }

    private func performSync(serverID: String, accounts: [Account], change: CouchPreset?) async {
        let fetched = await Self.fetchAll(accounts)

        for failure in fetched where failure.customPrefs == nil {
            logger.error(
                "Couch presets: reading prefs of user \(failure.account.userID) failed: \(failure.error?.localizedDescription ?? "unknown error")"
            )
        }

        let reachable = fetched.filter { $0.customPrefs != nil }

        guard reachable.isEmpty == false else { return }

        let remote = reachable.map { CouchPresetSync.presets(in: $0.customPrefs ?? [:]) }

        // Local first: what this device knows (including changes that never reached the server) is merged in
        var merged = CouchPresetSync.merge([allByServerID[serverID] ?? [:]] + remote)
        if let change {
            merged[change.id] = CouchPresetSync.newest(merged[change.id], change)
        }

        setAll(merged, serverID: serverID)

        let now = Date.now
        let writes: [(Account, [String: String])] = reachable.compactMap { fetched in
            let customPrefs = fetched.customPrefs ?? [:]
            let stored = CouchPresetSync.presets(in: customPrefs)

            guard CouchPresetSync.needsWrite(stored: stored, merged: merged, now: now) else { return nil }

            return (
                fetched.account,
                CouchPresetSync.customPrefsForWriting(existing: customPrefs, merged: merged, now: now)
            )
        }

        guard writes.isEmpty == false else { return }

        let errors = await Self.postAll(writes)

        for error in errors {
            logger.error("Couch presets: saving prefs failed: \(error.localizedDescription)")
        }
    }

    // MARK: Network (nonisolated, runs in parallel)

    private nonisolated static func fetchAll(_ accounts: [Account]) async -> [Fetched] {
        await withTaskGroup(of: Fetched.self) { group in
            for account in accounts {
                group.addTask {
                    do {
                        let customPrefs = try await CouchDisplayPreferences.fetchCustomPrefs(
                            displayPreferencesID: CouchPresetSync.displayPreferencesID,
                            userID: account.userID,
                            client: account.client
                        )
                        return Fetched(account: account, customPrefs: customPrefs, error: nil)
                    } catch {
                        return Fetched(account: account, customPrefs: nil, error: error)
                    }
                }
            }

            var results: [Fetched] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
    }

    /// - Returns: the errors of the failed writes
    private nonisolated static func postAll(_ writes: [(Account, [String: String])]) async -> [Error] {
        await withTaskGroup(of: Error?.self) { group in
            for (account, customPrefs) in writes {
                group.addTask {
                    do {
                        try await CouchDisplayPreferences.postCustomPrefs(
                            customPrefs,
                            displayPreferencesID: CouchPresetSync.displayPreferencesID,
                            userID: account.userID,
                            client: account.client
                        )
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
}
