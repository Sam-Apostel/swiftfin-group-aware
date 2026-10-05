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

    var couchKidsStore: Factory<CouchKidsStore> {
        self { @MainActor in CouchKidsStore() }
            .singleton
    }
}

/// Syncs the kid flags (`UserState.isKid`) household-wide.
///
/// The flags are stored in the Jellyfin DisplayPreferences row `swiftfin-couch-kids` (client `swiftfin-couch`)
/// of **every** stored user on the server that has a token, as one JSON map `[userID: CouchKidFlag]`.
/// Rows are merged per user (newest `updatedAt` wins, a tie prefers the kid flag, see `CouchKidsSync`),
/// applied locally without pushing again, and every account whose row differs gets the full merged map.
///
/// The picker runs signed out, so the store builds inert member clients from the stored users itself.
/// A failed fetch leaves the local flags as they are.
@MainActor
final class CouchKidsStore: ObservableObject {

    /// Goes up whenever a local kid flag changes (from the UI or from the sync).
    @Published
    private(set) var revision: Int = 0

    /// When a refresh last read at least one account's row.
    private(set) var lastRefreshDate: Date?

    private var syncChain: Task<Void, Never>?
    private var clients: [String: JellyfinClient] = [:]

    private let logger = Logger.swiftfin()

    init() {}

    /// Reads the kids row of every stored user on `server` that has a token, merges them with the
    /// local flags, applies the result locally and writes it to every account whose row differs.
    ///
    /// Never throws; failures are logged. Syncs run one at a time, so this may wait for a running one.
    func refresh(server: ServerState, users: [UserState]) async {
        let task = enqueueSync(server: server, users: users)
        await task.value
    }

    /// Pushes a kid flag changed in the UI to every account on its server. Fire-and-forget.
    func didToggle(userID: String, serverID: String) {
        revision += 1

        guard let server = StoredValues[.Server.servers].first(where: { $0.id == serverID }) else {
            logger.warning("Kid flags: no stored server for user \(userID), kept on this device only")
            return
        }

        let users = StoredValues[.User.users].filter { $0.serverID == serverID }

        _ = enqueueSync(server: server, users: users)
    }
}

// MARK: - Sync

extension CouchKidsStore {

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
    private func enqueueSync(server: ServerState, users: [UserState]) -> Task<Void, Never> {
        let accounts = makeAccounts(server: server, users: users)
        let serverID = server.id
        let previous = syncChain

        let task = Task { @MainActor [weak self] in
            await previous?.value

            guard let self else { return }

            if accounts.isEmpty {
                self.logger.warning("Kid flags: no user with an access token on this server, kept on this device only")
            } else {
                await self.performSync(serverID: serverID, accounts: accounts)
            }
        }

        syncChain = task
        return task
    }

    private func performSync(serverID: String, accounts: [Account]) async {
        let fetched = await Self.fetchAll(accounts)

        for failure in fetched where failure.customPrefs == nil {
            logger.error(
                "Kid flags: reading prefs of user \(failure.account.userID) failed: \(failure.error?.localizedDescription ?? "unknown error")"
            )
        }

        let reachable = fetched.filter { $0.customPrefs != nil }

        // A failed fetch leaves the local flags as they are
        guard reachable.isNotEmpty else { return }

        lastRefreshDate = .now

        // Read the local flags after the fetch, so a toggle made meanwhile is included
        let localUsers = Self.uniqueUsers(StoredValues[.User.users].filter { $0.serverID == serverID })
        let local = Self.localFlags(of: localUsers)
        let localKidIDs = Set(localUsers.filter(\.isKid).map(\.id))
        let remote = reachable.map { CouchKidsSync.flags(in: $0.customPrefs ?? [:]) }

        let merged = CouchKidsSync.seeded(
            remote: CouchKidsSync.merge(remote + [local]),
            localKidIDs: localKidIDs,
            now: .now
        )

        apply(merged, to: localUsers)

        let writes: [(Account, [String: String])] = reachable.compactMap { fetched in
            let customPrefs = fetched.customPrefs ?? [:]
            let stored = CouchKidsSync.flags(in: customPrefs)

            guard CouchKidsSync.needsWrite(stored: stored, merged: merged) else { return nil }
            guard let customPrefsForWriting = CouchKidsSync.customPrefsForWriting(existing: customPrefs, merged: merged) else {
                return nil
            }

            return (fetched.account, customPrefsForWriting)
        }

        guard writes.isNotEmpty else { return }

        let errors = await Self.postAll(writes)

        for error in errors {
            logger.error("Kid flags: saving prefs failed: \(error.localizedDescription)")
        }
    }

    /// Writes the merged flags to the local users, without pushing them again.
    private func apply(_ merged: [String: CouchKidFlag], to users: [UserState]) {
        var didChangeKid = false

        for user in users {
            guard let flag = merged[user.id] else { continue }

            let wasKid = user.isKid

            guard wasKid != flag.isKid || user.kidUpdatedAt != flag.updatedAt else { continue }

            user.applySyncedKid(flag.isKid, updatedAt: flag.updatedAt)

            if wasKid != flag.isKid {
                didChangeKid = true
                logger.info("Kid flags: user \(user.id) is \(flag.isKid ? "now" : "no longer") a kid (synced)")
            }
        }

        if didChangeKid {
            revision += 1
        }
    }

    /// The local flags that carry a timestamp. A flag without one is never published as is.
    private static func localFlags(of users: [UserState]) -> [String: CouchKidFlag] {
        var flags: [String: CouchKidFlag] = [:]

        for user in users {
            guard let updatedAt = user.kidUpdatedAt else { continue }

            flags[user.id] = CouchKidFlag(isKid: user.isKid, updatedAt: updatedAt, updatedBy: nil)
        }

        return flags
    }

    private static func uniqueUsers(_ users: [UserState]) -> [UserState] {
        var seenIDs: Set<String> = []
        return users.filter { seenIDs.insert($0.id).inserted }
    }

    // MARK: Network (nonisolated, runs in parallel)

    private nonisolated static func fetchAll(_ accounts: [Account]) async -> [Fetched] {
        await withTaskGroup(of: Fetched.self) { group in
            for account in accounts {
                group.addTask {
                    do {
                        let customPrefs = try await CouchDisplayPreferences.fetchCustomPrefs(
                            displayPreferencesID: CouchKidsSync.displayPreferencesID,
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
                            displayPreferencesID: CouchKidsSync.displayPreferencesID,
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
