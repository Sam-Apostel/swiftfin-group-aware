//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import FactoryKit
import Foundation
import JellyfinAPI
import Logging

// MARK: - Household Seerr server

/// What a DisplayPreferences call needs from a household `UserSession`, safe to pass to child tasks.
private struct SeerrHouseholdAccount: Sendable {
    let userID: String
    let client: JellyfinClient
}

/// The custom prefs of one household account; `nil` when reading them failed.
private struct SeerrHouseholdPrefs: Sendable {
    let account: SeerrHouseholdAccount
    let customPrefs: [String: String?]?
}

/// The household's Seerr server URL, synced through the Jellyfin DisplayPreferences of every household
/// account (`swiftfin-couch-seerr`, client `swiftfin-couch`), so an Apple TV finds the server without typing.
///
/// Only the URL is shared. The admin API key, session cookies and the version never leave the device:
/// each device signs in on its own.
///
/// - Publishing: after an explicit connect (`SeerrSettingsViewModel.connect(url:apiKey:)`), and a one-time
///   backfill for devices set up before this existed. Disconnecting doesn't publish.
/// - Adoption: tvOS only. iPhones never adopt the household URL.
@MainActor
extension SeerrService {

    /// Jellyfin servers checked for a backfill since launch.
    private static var householdBackfilledServerIDs: Set<String> = []
    /// Household writes run one at a time: each one is a read-modify-write per account.
    private static var householdWriteChain: Task<Void, Never>?

    #if os(tvOS)
    private static var householdAdoptionTask: Task<URL?, Error>?
    #endif

    private static var householdLogger: Logger {
        Logger.swiftfin()
    }

    // MARK: - Publish

    /// Publishes `serverURL` (the current one) to every household account. Best effort, logs, never throws.
    ///
    /// Call it after an explicit, successful connect: it also marks this device's URL as chosen here,
    /// so an Apple TV never replaces it with the household's (`adoptHouseholdServerIfNeeded()`).
    func publishHouseholdServer() {
        guard let session = Container.shared.currentUserSession() else { return }

        Defaults[Self.householdAdoptedKey(serverID: session.server.id)] = false

        publishHouseholdServer(session: session)
    }

    private func publishHouseholdServer(session: UserSession) {
        guard let serverURL else { return }

        // An explicit publish makes the backfill unnecessary
        Self.householdBackfilledServerIDs.insert(session.server.id)

        let config = SeerrHouseholdConfig(
            serverURL: serverURL.absoluteString,
            updatedAt: .now,
            updatedBy: session.user.id
        )
        let accounts = Self.householdAccounts(of: session)

        guard accounts.isNotEmpty else {
            Self.householdLogger.warning("Seerr household: no account with an access token, the server URL isn't shared")
            return
        }

        let previous = Self.householdWriteChain

        Self.householdWriteChain = Task {
            await previous?.value
            await Self.writeHouseholdConfig(config, to: accounts)
        }
    }

    // MARK: - Read

    /// The newest household Seerr URL, or `nil` (none, unreachable, or invalid).
    func householdServerURL() async -> URL? {
        guard let session = Container.shared.currentUserSession() else { return nil }

        let accounts = Self.householdAccounts(of: session)

        guard accounts.isNotEmpty else { return nil }

        let fetched = await Self.fetchHouseholdPrefs(accounts)
        let configs = fetched.compactMap { prefs in
            SeerrHouseholdConfigSync.decode(prefs.customPrefs?[SeerrHouseholdConfigSync.key] ?? nil)
        }

        guard let newest = SeerrHouseholdConfigSync.newest(configs) else { return nil }
        guard let url = SeerrClient.serverURL(from: newest.serverURL) else {
            Self.householdLogger.error(
                "Seerr household: the shared server URL is invalid",
                metadata: ["updatedBy": .string(newest.updatedBy)]
            )
            return nil
        }

        return url
    }

    // MARK: - Adopt

    /// tvOS: adopts or follows the household URL.
    ///
    /// - No Seerr URL on this device yet: configures the newest household URL (Quick Connect, no API key).
    /// - Adopted earlier and the household URL changed: follows it; the old sessions end, the couch signs in again.
    /// - A URL entered on this device: never replaced.
    ///
    /// Adoption never publishes, so an Apple TV never bumps the household record by itself.
    ///
    /// - Returns: the URL it configured, `nil` when nothing changed. iOS: always `nil`.
    /// - Throws: what `configure(url:)` throws (e.g. Seerr < 3.4, unreachable).
    @discardableResult
    func adoptHouseholdServerIfNeeded() async throws -> URL? {
        #if os(tvOS)
        if let householdAdoptionTask = Self.householdAdoptionTask {
            return try await householdAdoptionTask.value
        }

        let task = Task { @MainActor in
            try await self.performHouseholdAdoption()
        }

        Self.householdAdoptionTask = task
        defer { Self.householdAdoptionTask = nil }

        return try await task.value
        #else
        return nil
        #endif
    }

    #if os(tvOS)
    private func performHouseholdAdoption() async throws -> URL? {
        guard let serverID = Container.shared.currentUserSession()?.server.id else { return nil }

        let adoptedKey = Self.householdAdoptedKey(serverID: serverID)

        // Entered on this device: never replaced
        if serverURL != nil, !Defaults[adoptedKey] {
            return nil
        }

        guard let householdURL = await householdServerURL() else { return nil }

        // The user switched servers, or connected by hand, while reading
        guard Container.shared.currentUserSession()?.server.id == serverID else { return nil }

        if let serverURL {
            guard Defaults[adoptedKey] else { return nil }
            guard serverURL.absoluteString != householdURL.absoluteString else { return nil }
        }

        Self.householdLogger.info(
            "Seerr household: adopting the household server",
            metadata: ["host": .string(householdURL.host ?? householdURL.absoluteString)]
        )

        try await configure(url: householdURL)

        Defaults[adoptedKey] = true

        return householdURL
    }
    #endif

    // MARK: - Backfill

    /// Once per Jellyfin server per launch: publish when no household account has the key yet.
    ///
    /// For devices set up before the household URL existed. Never overwrites an existing record:
    /// it only publishes when every household account could be read and none has one.
    func backfillHouseholdServerIfNeeded() {
        guard serverURL != nil, let session = Container.shared.currentUserSession() else { return }

        let serverID = session.server.id

        guard Self.householdBackfilledServerIDs.insert(serverID).inserted else { return }

        let accounts = Self.householdAccounts(of: session)

        guard accounts.isNotEmpty else { return }

        Task { @MainActor [weak self] in
            let fetched = await Self.fetchHouseholdPrefs(accounts)

            guard fetched.allSatisfy({ $0.customPrefs != nil }) else {
                Self.householdLogger.warning("Seerr household: couldn't read every account, skipping the backfill")
                return
            }

            let hasRecord = fetched.contains { prefs in
                SeerrHouseholdConfigSync.decode(prefs.customPrefs?[SeerrHouseholdConfigSync.key] ?? nil) != nil
            }

            guard !hasRecord,
                  let self,
                  self.serverURL != nil,
                  let currentSession = Container.shared.currentUserSession(),
                  currentSession.server.id == serverID
            else { return }

            Self.householdLogger.info("Seerr household: sharing this device's Seerr server URL with the household")

            self.publishHouseholdServer(session: currentSession)
        }
    }

    // MARK: - Helpers

    /// Whether this device's URL came from the household (tvOS adoption), per Jellyfin server.
    private static func householdAdoptedKey(serverID: String) -> Defaults.Key<Bool> {
        // Defaults key names can't contain dots
        Defaults.Key<Bool>(
            "seerrHouseholdAdopted_\(serverID.replacing(".", with: "_"))",
            default: false,
            suite: .appSuite
        )
    }

    /// Every household account on this device with a stored token, current user first.
    ///
    /// Filters on the token before touching `client`: a missing token would hit `UserState.accessToken`'s assertion.
    private static func householdAccounts(of session: UserSession) -> [SeerrHouseholdAccount] {
        session.householdSessions()
            .filter { $0.user.storedAccessToken != nil }
            .map { SeerrHouseholdAccount(userID: $0.user.id, client: $0.client) }
    }

    // MARK: Network (nonisolated, runs in parallel)

    /// The custom prefs of every account, in the order passed in. Failures are logged.
    private nonisolated static func fetchHouseholdPrefs(_ accounts: [SeerrHouseholdAccount]) async -> [SeerrHouseholdPrefs] {
        await withTaskGroup(of: (Int, SeerrHouseholdPrefs).self) { group in
            for (offset, account) in accounts.enumerated() {
                group.addTask {
                    do {
                        let customPrefs = try await CouchDisplayPreferences.fetchCustomPrefs(
                            displayPreferencesID: SeerrHouseholdConfigSync.displayPreferencesID,
                            userID: account.userID,
                            client: account.client
                        )
                        return (offset, SeerrHouseholdPrefs(account: account, customPrefs: customPrefs))
                    } catch {
                        Logger.swiftfin().error(
                            "Seerr household: reading the shared server failed",
                            metadata: [
                                "userID": .string(account.userID),
                                "error": .string(error.localizedDescription),
                            ]
                        )
                        return (offset, SeerrHouseholdPrefs(account: account, customPrefs: nil))
                    }
                }
            }

            var results: [(Int, SeerrHouseholdPrefs)] = []
            for await result in group {
                results.append(result)
            }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    /// GET → keep every non-nil `sgw.` key → set ours → POST, for each account. Failures are logged.
    private nonisolated static func writeHouseholdConfig(_ config: SeerrHouseholdConfig, to accounts: [SeerrHouseholdAccount]) async {
        let fetched = await fetchHouseholdPrefs(accounts)

        await withTaskGroup(of: Void.self) { group in
            for prefs in fetched {
                // POST replaces the whole map: never write over prefs we couldn't read
                guard let existing = prefs.customPrefs else { continue }

                let account = prefs.account
                let customPrefs = SeerrHouseholdConfigSync.customPrefsForWriting(existing: existing, config: config)

                group.addTask {
                    do {
                        try await CouchDisplayPreferences.postCustomPrefs(
                            customPrefs,
                            displayPreferencesID: SeerrHouseholdConfigSync.displayPreferencesID,
                            userID: account.userID,
                            client: account.client
                        )
                    } catch {
                        Logger.swiftfin().error(
                            "Seerr household: sharing the server URL failed",
                            metadata: [
                                "userID": .string(account.userID),
                                "error": .string(error.localizedDescription),
                            ]
                        )
                    }
                }
            }
        }
    }
}
