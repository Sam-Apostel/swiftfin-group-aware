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
import Logging

@MainActor
final class SeerrSettingsViewModel: ObservableObject {

    // MARK: - Person

    /// A Jellyfin user stored on this device for the current server,
    /// with the Seerr account their requests are made as.
    struct Person: Hashable, Identifiable {

        enum Mapping: Hashable {
            case loading
            /// Already had a Seerr account.
            case mapped(seerrName: String)
            /// Was just imported from Jellyfin into Seerr.
            case imported(seerrName: String)
            case notFound
        }

        let user: UserState
        var mapping: Mapping

        var id: String {
            user.id
        }
    }

    // MARK: - Published

    @Published
    private(set) var isConnecting = false
    @Published
    private(set) var people: [Person] = []
    @Published
    private(set) var version: String?

    @Published
    var error: Error?

    // MARK: - Private

    @Injected(\.seerrService)
    private var seerrService: SeerrService

    private let logger = Logger.swiftfin()
    private var refreshTask: Task<Void, Never>?

    /// The Jellyfin server of the current session. Each Jellyfin server has its own Seerr configuration.
    var server: ServerState? {
        Container.shared.currentUserSession()?.server
    }

    // MARK: - Load

    func load() {
        guard seerrService.isConfigured else {
            refreshTask?.cancel()
            version = nil
            people = []
            return
        }

        refresh()
    }

    // MARK: - Connect

    /// Validates and saves the Seerr connection.
    /// Returns `true` on success; on failure `error` is set.
    func connect(url: String, apiKey: String) async -> Bool {
        guard !isConnecting else { return false }
        guard let serverURL = SeerrClient.serverURL(from: url) else {
            error = ErrorMessage(L10n.Seerr.errorInvalidURL)
            return false
        }

        let apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard apiKey.isNotEmpty else {
            error = ErrorMessage(L10n.SeerrSettings.missingAPIKey)
            return false
        }

        isConnecting = true
        defer { isConnecting = false }

        do {
            try await seerrService.configure(url: serverURL, apiKey: apiKey)
        } catch is CancellationError {
            return false
        } catch {
            logger.error(
                "Failed to connect to Seerr",
                metadata: ["error": .string(error.localizedDescription)]
            )
            self.error = error
            return false
        }

        refresh()
        return true
    }

    // MARK: - Disconnect

    func disconnect() {
        refreshTask?.cancel()
        refreshTask = nil

        seerrService.disconnect()

        version = nil
        people = []
    }

    // MARK: - Refresh

    private func refresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.refreshVersion()
            await self?.refreshPeople()
        }
    }

    private func refreshVersion() async {
        guard let client = seerrService.client else {
            version = nil
            return
        }

        do {
            let status = try await client.status()

            guard !Task.isCancelled else { return }

            version = status.version
        } catch {
            guard !Task.isCancelled else { return }

            logger.warning(
                "Failed to get the Seerr status",
                metadata: ["error": .string(error.localizedDescription)]
            )
            version = nil
        }
    }

    private func refreshPeople() async {
        guard let server, let client = seerrService.client else {
            people = []
            return
        }

        let currentUserID = Container.shared.currentUserSession()?.user.id

        let users = StoredValues[.User.users]
            .filter { $0.serverID == server.id }
            .sorted { lhs, rhs in
                if lhs.id == currentUserID {
                    return true
                }
                if rhs.id == currentUserID {
                    return false
                }
                return lhs.username.localizedCaseInsensitiveCompare(rhs.username) == .orderedAscending
            }

        people = users.map { Person(user: $0, mapping: .loading) }

        // Seerr users that exist before mapping, to tell "found" from "imported".
        // `nil` when the list can't be fetched: everyone mapped then shows as found.
        let existingSeerrUsers: [SeerrUser]?

        do {
            existingSeerrUsers = try await client.users()
        } catch {
            logger.warning(
                "Failed to list Seerr users",
                metadata: ["error": .string(error.localizedDescription)]
            )
            existingSeerrUsers = nil
        }

        // Sequential on purpose: mapping may import users into Seerr,
        // and the service caches each result.
        for user in users {
            guard !Task.isCancelled else { return }

            let existingSeerrUser = existingSeerrUsers?.first { $0.matches(jellyfinUserID: user.id) }
            let newMapping = await resolveMapping(
                for: user,
                client: client,
                existingSeerrUser: existingSeerrUser,
                canDetectImport: existingSeerrUsers != nil
            )

            guard !Task.isCancelled else { return }

            if let index = people.firstIndex(where: { $0.id == user.id }) {
                people[index].mapping = newMapping
            }
        }
    }

    private func resolveMapping(
        for user: UserState,
        client: SeerrClient,
        existingSeerrUser: SeerrUser?,
        canDetectImport: Bool
    ) async -> Person.Mapping {

        // Already in Seerr: no lookup or import needed.
        if let existingSeerrUser {
            return .mapped(seerrName: existingSeerrUser.displayName ?? user.username)
        }

        guard let seerrUserID = await seerrService.seerrUserID(for: user) else {
            return .notFound
        }

        let name = await seerrName(for: user, seerrUserID: seerrUserID, client: client)

        if canDetectImport {
            return .imported(seerrName: name)
        } else {
            return .mapped(seerrName: name)
        }
    }

    private func seerrName(for user: UserState, seerrUserID: Int, client: SeerrClient) async -> String {
        do {
            let seerrUser = try await client.me(asUser: seerrUserID)

            if let displayName = seerrUser.displayName, displayName.isNotEmpty {
                return displayName
            } else {
                return user.username
            }
        } catch {
            logger.warning(
                "Failed to get the Seerr user",
                metadata: ["error": .string(error.localizedDescription)]
            )
            return user.username
        }
    }
}
