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
import KeychainSwift
import Logging
import Pulse

extension Container {

    var seerrService: Factory<SeerrService> {
        self { @MainActor in SeerrService() }
            .singleton
    }
}

/// Owns the `SeerrClient` for the current Jellyfin server.
///
/// Each Jellyfin server has its own Seerr configuration: the URL is stored in
/// `Defaults` (app suite) and the admin API key in the Keychain, both keyed by
/// the Jellyfin server id. The client is rebuilt automatically when the user
/// session changes; call `reload()` to force it.
@MainActor
final class SeerrService: ObservableObject {

    /// `nil` when Seerr is not configured for the current Jellyfin server.
    @Published
    private(set) var client: SeerrClient?

    var isConfigured: Bool {
        client != nil
    }

    /// The configured Seerr server URL (without `/api/v1`).
    var serverURL: URL? {
        client?.baseURL
    }

    private let logger = Logger.swiftfin()
    private var cancellables: Set<AnyCancellable> = []

    init() {
        reload()

        Container.shared
            .userSessionManager()
            .$currentSession
            .map { $0?.server.id }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] serverID in
                Task { @MainActor in
                    self?.load(serverID: serverID)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Configuration

    /// Validates the server and API key, then persists them for the current Jellyfin server.
    ///
    /// - Throws: `SeerrError.unauthorized` for a rejected key, `SeerrError.server` / `URLError`
    ///           when the server can't be reached, or an `ErrorMessage` for invalid input.
    func configure(url: URL, apiKey: String) async throws {
        guard let serverID = currentServerID else {
            throw ErrorMessage(L10n.Seerr.errorNoServer)
        }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", url.host != nil else {
            throw ErrorMessage(L10n.Seerr.errorInvalidURL)
        }

        let apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard apiKey.isEmpty == false else {
            throw SeerrError.unauthorized
        }

        let newClient = Self.makeClient(url: url, apiKey: apiKey)

        do {
            // Reachability (public), then the API key
            let status = try await newClient.status()
            let user = try await newClient.me()

            logger.info(
                "Connected to Seerr",
                metadata: [
                    "version": .string(status.version),
                    "userID": .stringConvertible(user.id),
                ]
            )
        } catch {
            logger.error(
                "Failed to connect to Seerr",
                metadata: ["error": .string(error.localizedDescription)]
            )
            throw error
        }

        Defaults[Self.serverURLKey(serverID: serverID)] = newClient.baseURL.absoluteString
        keychain.set(apiKey, forKey: Self.apiKeyKeychainKey(serverID: serverID))

        // The user may have switched servers while validating
        if currentServerID == serverID {
            client = newClient
        }
    }

    /// Removes the Seerr configuration of the current Jellyfin server.
    func disconnect() {
        if let serverID = currentServerID {
            Defaults[Self.serverURLKey(serverID: serverID)] = nil
            keychain.delete(Self.apiKeyKeychainKey(serverID: serverID))
        }

        client = nil
    }

    /// Rebuilds the client for the current Jellyfin server.
    func reload() {
        load(serverID: currentServerID)
    }

    // MARK: - Users

    /// The Seerr user id for a Jellyfin user, importing them into Seerr if needed.
    ///
    /// - Returns: `nil` when Seerr isn't configured or the lookup fails.
    func seerrUserID(for user: UserState) async -> Int? {
        await seerrUserID(forJellyfinUserID: user.id)
    }

    /// The Seerr user id for a Jellyfin user id, importing them into Seerr if needed.
    ///
    /// - Returns: `nil` when Seerr isn't configured or the lookup fails.
    func seerrUserID(forJellyfinUserID jellyfinUserID: String) async -> Int? {
        guard let client else { return nil }

        do {
            let seerrUserID = try await client.seerrUserID(forJellyfinUserID: jellyfinUserID)

            if seerrUserID == nil {
                logger.warning(
                    "No Seerr user for Jellyfin user",
                    metadata: ["jellyfinUserID": .string(jellyfinUserID)]
                )
            }

            return seerrUserID
        } catch {
            logger.error(
                "Failed to map Jellyfin user to Seerr user",
                metadata: [
                    "jellyfinUserID": .string(jellyfinUserID),
                    "error": .string(error.localizedDescription),
                ]
            )
            return nil
        }
    }

    // MARK: - Private

    private var keychain: KeychainSwift {
        Container.shared.keychainService()
    }

    private var currentServerID: String? {
        Container.shared.currentUserSession()?.server.id
    }

    private func load(serverID: String?) {
        guard let serverID,
              let urlString = Defaults[Self.serverURLKey(serverID: serverID)],
              let url = URL(string: urlString),
              let apiKey = keychain.get(Self.apiKeyKeychainKey(serverID: serverID)),
              apiKey.isEmpty == false
        else {
            client = nil
            return
        }

        client = Self.makeClient(url: url, apiKey: apiKey)
    }

    private static func makeClient(url: URL, apiKey: String) -> SeerrClient {
        SeerrClient(
            baseURL: url,
            apiKey: apiKey,
            sessionConfiguration: .swiftfin,
            sessionDelegate: URLSessionProxyDelegate(logger: NetworkLogger.seerr())
        )
    }

    /// Defaults key names can't contain dots.
    private static func storageID(_ serverID: String) -> String {
        serverID.replacing(".", with: "_")
    }

    private static func serverURLKey(serverID: String) -> Defaults.Key<String?> {
        Defaults.Key<String?>("seerrServerURL_\(storageID(serverID))", suite: .appSuite)
    }

    private static func apiKeyKeychainKey(serverID: String) -> String {
        "seerrAPIKey-\(serverID)"
    }
}

// MARK: - NetworkLogger

extension NetworkLogger {

    /// A Pulse network logger for Seerr that redacts the admin API key.
    static func seerr() -> NetworkLogger {
        var configuration = NetworkLogger.Configuration()
        // Pulse 5.2.3 drops its `.caseInsensitive` option for these patterns, so list each casing
        configuration.sensitiveHeaders = [
            "X-Api-Key", "x-api-key", "X-API-Key", "X-API-KEY",
            "Cookie", "cookie", "Set-Cookie", "set-cookie",
        ]
        configuration.sensitiveDataFields = ["apiKey", "password", "plexToken", "jellyfinAuthToken"]
        return NetworkLogger(configuration: configuration)
    }
}
