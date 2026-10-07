//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if os(tvOS)
import Defaults
import FactoryKit
import Foundation
import JellyfinAPI
import Logging

/// The household: everything every Apple TV profile shares.
///
/// Couchfin runs as the current Apple TV user, so its preferences and files are kept
/// per Apple TV profile. Only the user-independent keychain is shared. This keeps one
/// copy of the household there (servers, people, connections, lock settings, who's a kid,
/// Seerr addresses) and makes it the source of truth: every launch copies it into the
/// profile's own storage, and every change is written back. Access tokens, PINs and Seerr
/// secrets are already in the shared keychain (`CouchfinKeychain`).
@MainActor
enum HouseholdStore {

    struct Household: Codable {

        var servers: [ServerState]
        var users: [UserState]
        var connections: [String: [ServerConnection]]
        var activeConnectionIDs: [String: String]
        var userData: [String: UserDto]
        var accessPolicies: [String: LocalUserAccessPolicy]
        var pinHints: [String: String]
        var kidUserIDs: [String]
        var seerrServerURLs: [String: String]
        var updatedAt: Date
    }

    private static let keychainKey = "couchfin-household"
    private static let logger = Logger.swiftfin()

    private static var isRestoring = false
    private static var pendingSave: Task<Void, Never>?

    // MARK: - Restore

    /// Copies the household into this profile's storage. The first time (no household yet),
    /// this profile's storage seeds it.
    static func restore() {
        guard let household = load() else {
            save()
            return
        }

        isRestoring = true
        defer { isRestoring = false }

        StoredValues[.Server.servers] = household.servers
        StoredValues[.User.users] = household.users

        for server in household.servers {
            StoredValues[.Server.connections(id: server.id)] = household.connections[server.id] ?? []
            StoredValues[.Server.activeConnectionID(id: server.id)] = household.activeConnectionIDs[server.id] ?? .empty
            Defaults[SeerrService.serverURLKey(serverID: server.id)] = household.seerrServerURLs[server.id]
        }

        let kidUserIDs = Set(household.kidUserIDs)

        for user in household.users {
            if let data = household.userData[user.id] {
                StoredValues[.User.data(id: user.id)] = data
            }

            StoredValues[.User.accessPolicy(id: user.id)] = household.accessPolicies[user.id] ?? .none
            StoredValues[.User.pinHint(id: user.id)] = household.pinHints[user.id] ?? .empty
            user.isKid = kidUserIDs.contains(user.id)
        }

        logger.info("Household: restored \(household.servers.count) servers and \(household.users.count) people")
    }

    // MARK: - Save

    /// Whether a change to this stored value has to reach the other Apple TV profiles.
    nonisolated static func isShared(field: String?) -> Bool {
        guard let field else { return false }

        return [
            "servers",
            "users",
            "serverConnections",
            "activeServerConnectionID",
            "userData",
            "accessPolicy",
            "pinHint",
            "couchIsKid",
        ].contains(field)
    }

    /// Writes the household back soon, coalescing a burst of changes into one write.
    static func scheduleSave() {
        guard !isRestoring else { return }

        pendingSave?.cancel()
        pendingSave = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }

            save()
        }
    }

    /// Writes this profile's copy of the household to the shared keychain.
    static func save() {
        let servers = StoredValues[.Server.servers]
        let users = StoredValues[.User.users]

        var household = Household(
            servers: servers,
            users: users,
            connections: [:],
            activeConnectionIDs: [:],
            userData: [:],
            accessPolicies: [:],
            pinHints: [:],
            kidUserIDs: [],
            seerrServerURLs: [:],
            updatedAt: .now
        )

        for server in servers {
            household.connections[server.id] = StoredValues[.Server.connections(id: server.id)]
            household.activeConnectionIDs[server.id] = StoredValues[.Server.activeConnectionID(id: server.id)]
            household.seerrServerURLs[server.id] = Defaults[SeerrService.serverURLKey(serverID: server.id)]
        }

        moveSecretsToSharedKeychain(servers: servers, users: users)

        for user in users {
            household.userData[user.id] = StoredValues[.User.data(id: user.id)]
            household.accessPolicies[user.id] = StoredValues[.User.accessPolicy(id: user.id)]
            household.pinHints[user.id] = StoredValues[.User.pinHint(id: user.id)]

            if user.isKid {
                household.kidUserIDs.append(user.id)
            }
        }

        do {
            let data = try JSONEncoder().encode(household)
            guard let json = String(data: data, encoding: .utf8) else { return }

            Container.shared.keychainService().set(json, forKey: keychainKey)
        } catch {
            logger.error("Household: could not save: \(error.localizedDescription)")
        }
    }

    /// Reading a secret moves it from this profile's keychain to the shared one
    /// (see `CouchfinKeychain`), so other profiles can use people this profile signed in.
    private static func moveSecretsToSharedKeychain(servers: [ServerState], users: [UserState]) {
        let keychain = Container.shared.keychainService()

        for user in users {
            _ = keychain.get("\(user.id)-accessToken")
            _ = keychain.get("\(user.id)-pin")
            _ = keychain.get(SeerrService.sessionKeychainKey(serverID: user.serverID, jellyfinUserID: user.id))
        }

        for server in servers {
            _ = keychain.get(SeerrService.apiKeyKeychainKey(serverID: server.id))
        }
    }

    private static func load() -> Household? {
        guard let json = Container.shared.keychainService().get(keychainKey),
              let data = json.data(using: .utf8)
        else { return nil }

        do {
            return try JSONDecoder().decode(Household.self, from: data)
        } catch {
            logger.error("Household: could not read: \(error.localizedDescription)")
            return nil
        }
    }
}
#endif
