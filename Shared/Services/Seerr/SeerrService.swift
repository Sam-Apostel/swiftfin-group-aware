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
import KeychainSwift
import Logging
import Pulse

extension Container {

    var seerrService: Factory<SeerrService> {
        self { @MainActor in SeerrService() }
            .singleton
    }
}

/// Owns the `SeerrClient`s for the current Jellyfin server.
///
/// Each Jellyfin server has its own Seerr configuration: the URL is stored in
/// `Defaults` (app suite), the optional admin API key and each person's Seerr
/// session (from Jellyfin Quick Connect) in the Keychain, all keyed by the
/// Jellyfin server id. The clients are rebuilt automatically when the user
/// session changes; call `reload()` to force it.
///
/// - `client` is for browsing: the API key client when there is a key,
///   otherwise the session of the current (or another signed-in) person.
/// - `perform(asJellyfinUserID:_:)` acts as one person (requests, watchlists):
///   with their own session when they have one, else the API key + `X-Api-User`.
@MainActor
final class SeerrService: ObservableObject {

    /// `nil` when Seerr can't be used for the current Jellyfin server:
    /// not configured, or no API key and nobody signed in with Quick Connect.
    @Published
    private(set) var client: SeerrClient?

    /// The configured Seerr server URL (without `/api/v1`).
    ///
    /// Set as soon as a server is saved, also before anyone signed in with Quick Connect.
    @Published
    private(set) var serverURL: URL?

    /// Whether an admin API key is saved for the current Jellyfin server.
    @Published
    private(set) var hasAPIKey: Bool = false

    /// The Jellyfin user ids (current server) with a saved Quick Connect session.
    @Published
    private(set) var signedInUserIDs: Set<String> = []

    var isConfigured: Bool {
        client != nil
    }

    private let logger = Logger.swiftfin()
    private var cancellables: Set<AnyCancellable> = []

    /// The Jellyfin server the clients below belong to.
    private var loadedServerID: String?
    private var apiKeyClient: SeerrClient?
    private var cachedAnonymousClient: SeerrClient?
    /// API key clients that act as one Seerr user (`X-Api-User`), by Seerr user id.
    private var actingClients: [Int: SeerrClient] = [:]
    /// Session clients, by Jellyfin user id.
    private var sessionClients: [String: SeerrClient] = [:]
    private var signInTasks: [String: Task<SeerrUser, Error>] = [:]
    /// Session users whose browsing session was checked since the last load.
    private var checkedBrowsingUserIDs: Set<String> = []

    init() {
        reload()

        Container.shared
            .userSessionManager()
            .$currentSession
            .map { [$0?.server.id, $0?.user.id] }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] ids in
                Task { @MainActor in
                    self?.sessionDidChange(serverID: ids.first ?? nil)
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
        guard Self.isValidServerURL(url) else {
            throw ErrorMessage(L10n.Seerr.errorInvalidURL)
        }

        let apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard apiKey.isEmpty == false else {
            throw SeerrError.unauthorized
        }

        let newClient = Self.makeClient(url: url, auth: .apiKey(apiKey, asUser: nil))

        do {
            // Reachability (public), then the API key
            let serverStatus = try await newClient.status()
            let user = try await newClient.me()

            logger.info(
                "Connected to Seerr",
                metadata: [
                    "version": .string(serverStatus.version),
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

        endSessionsIfServerURLChanged(serverID: serverID, newURL: newClient.baseURL)

        Defaults[Self.serverURLKey(serverID: serverID)] = newClient.baseURL.absoluteString
        keychain.set(apiKey, forKey: Self.apiKeyKeychainKey(serverID: serverID))

        // The user may have switched servers while validating
        guard currentServerID == serverID else { return }

        if loadedServerID != serverID || serverURL != newClient.baseURL {
            load(serverID: serverID)
        }

        serverURL = newClient.baseURL
        apiKeyClient = newClient
        actingClients = [:]
        hasAPIKey = true
        client = newClient
    }

    /// Saves a Seerr server without an API key, for signing in with Jellyfin Quick Connect.
    ///
    /// A saved API key is kept unless the new server rejects it.
    ///
    /// - Throws: `SeerrError.server` / `URLError` when the server can't be reached, or an
    ///           `ErrorMessage` for invalid input or a server too old for Quick Connect.
    func configure(url: URL) async throws {
        guard let serverID = currentServerID else {
            throw ErrorMessage(L10n.Seerr.errorNoServer)
        }
        guard Self.isValidServerURL(url) else {
            throw ErrorMessage(L10n.Seerr.errorInvalidURL)
        }

        let probeClient = Self.makeClient(url: url, auth: nil)
        let serverStatus: SeerrStatus

        do {
            serverStatus = try await probeClient.status()
        } catch {
            logger.error(
                "Failed to reach Seerr",
                metadata: ["error": .string(error.localizedDescription)]
            )
            throw error
        }

        let apiKeyKey = Self.apiKeyKeychainKey(serverID: serverID)
        var savedAPIKey = keychain.get(apiKeyKey).flatMap { $0.isEmpty ? nil : $0 }
        var isSavedAPIKeyRejected = false

        if let apiKey = savedAPIKey {
            do {
                _ = try await Self.makeClient(url: url, auth: .apiKey(apiKey, asUser: nil)).me()
            } catch SeerrError.unauthorized {
                isSavedAPIKeyRejected = true
                savedAPIKey = nil
            } catch {
                // Keep the key on network hiccups
                logger.warning(
                    "Couldn't check the saved Seerr API key",
                    metadata: ["error": .string(error.localizedDescription)]
                )
            }
        }

        if savedAPIKey == nil, !SeerrClient.supportsQuickConnect(version: serverStatus.version) {
            throw ErrorMessage(L10n.SeerrQuickConnect.unsupportedVersion(serverStatus.version))
        }

        // Only now that the new server is accepted: a failed attempt keeps the old configuration intact
        if isSavedAPIKeyRejected {
            logger.info("The saved Seerr API key doesn't work with the new server, removing it")
            keychain.delete(apiKeyKey)
        }

        logger.info(
            "Saved Seerr server for Quick Connect",
            metadata: ["version": .string(serverStatus.version)]
        )

        endSessionsIfServerURLChanged(serverID: serverID, newURL: probeClient.baseURL)

        Defaults[Self.serverURLKey(serverID: serverID)] = probeClient.baseURL.absoluteString

        if currentServerID == serverID {
            load(serverID: serverID)
        }
    }

    /// Removes the Seerr configuration of the current Jellyfin server, including everyone's sessions.
    func disconnect() {
        if let serverID = currentServerID {
            for userID in storedUserIDs(serverID: serverID).union(signedInUserIDs) {
                endSession(serverID: serverID, jellyfinUserID: userID)
            }

            Defaults[Self.serverURLKey(serverID: serverID)] = nil
            keychain.delete(Self.apiKeyKeychainKey(serverID: serverID))
        }

        load(serverID: nil)
        loadedServerID = currentServerID
    }

    /// Removes the saved API key: from now on Seerr is only used through Quick Connect sessions.
    func removeAPIKey() {
        if let serverID = currentServerID {
            keychain.delete(Self.apiKeyKeychainKey(serverID: serverID))
        }

        apiKeyClient = nil
        actingClients = [:]
        hasAPIKey = false
        updateClient()
    }

    /// Rebuilds the clients for the current Jellyfin server.
    func reload() {
        load(serverID: currentServerID)
    }

    // MARK: - Acting as a person

    /// Runs `operation` with a client that acts as the given Jellyfin user:
    ///
    /// 1. Their own Quick Connect session, when they have one. If Seerr rejects it
    ///    because it expired, they are signed in again silently and `operation` is retried once.
    /// 2. Otherwise the API key with their Seerr user id (`X-Api-User`), importing them into Seerr if needed.
    /// 3. With `fallbackToAPIKeyOwner`, the API key owner when the person has no Seerr account.
    ///
    /// Calls inside `operation` don't need an `asUser`: the client already acts as the person.
    ///
    /// - Throws: whatever `operation` throws, or an `ErrorMessage` when no client can act as the person.
    func perform<Value>(
        asJellyfinUserID jellyfinUserID: String,
        fallbackToAPIKeyOwner: Bool = false,
        _ operation: (SeerrClient) async throws -> Value
    ) async throws -> Value {
        if let memberClient = sessionClient(forJellyfinUserID: jellyfinUserID) {
            do {
                return try await operation(memberClient)
            } catch SeerrError.unauthorized {
                // A 403 also means "missing permission": only an expired session fails `/auth/me`
                guard await Self.isSessionExpired(memberClient) else {
                    throw SeerrError.unauthorized
                }

                if let renewedClient = await renewSession(jellyfinUserID: jellyfinUserID) {
                    return try await operation(renewedClient)
                }

                if apiKeyClient == nil {
                    throw ErrorMessage(L10n.SeerrQuickConnect.errorNotSignedIn)
                }
            }
        }

        guard let apiKeyClient else {
            throw ErrorMessage(L10n.SeerrQuickConnect.errorNotSignedIn)
        }

        if let mappedUserID = await seerrUserID(forJellyfinUserID: jellyfinUserID),
           let userClient = actingClient(asUser: mappedUserID, apiKeyClient: apiKeyClient)
        {
            return try await operation(userClient)
        }

        guard fallbackToAPIKeyOwner else {
            throw ErrorMessage(L10n.SeerrQuickConnect.errorNoSeerrAccount)
        }

        logger.warning("No Seerr user for the Jellyfin user, acting as the API key owner")
        return try await operation(apiKeyClient)
    }

    // MARK: - Quick Connect

    /// `GET /status` of the configured server. Works before anyone signed in.
    func status() async throws -> SeerrStatus {
        guard let publicClient = client ?? anonymousClient() else {
            throw SeerrError.notConfigured
        }

        return try await publicClient.status()
    }

    /// The Jellyfin users that can sign in with Quick Connect from this device: the current
    /// user, and every other user of this server with a stored access token.
    func quickConnectEligibleUserIDs() -> Set<String> {
        Set(
            (Container.shared.currentUserSession()?.householdSessions() ?? [])
                .map(\.user.id)
        )
    }

    /// Signs a Jellyfin user in to Seerr with Jellyfin Quick Connect and saves their session.
    ///
    /// 1. Seerr starts a Quick Connect request (`initiate`).
    /// 2. The person's own Jellyfin session authorizes its code.
    /// 3. Seerr turns it into a session (`authenticate`), stored in the keychain.
    ///
    /// Concurrent calls for the same person share one sign-in.
    ///
    /// - Throws: an `ErrorMessage` explaining what to fix, or a `SeerrError` / `URLError`.
    @discardableResult
    func signInWithQuickConnect(jellyfinUserID: String) async throws -> SeerrUser {
        if let task = signInTasks[jellyfinUserID] {
            return try await task.value
        }

        let task = Task { @MainActor in
            try await self.quickConnectSignIn(jellyfinUserID: jellyfinUserID)
        }

        signInTasks[jellyfinUserID] = task
        defer { signInTasks[jellyfinUserID] = nil }

        return try await task.value
    }

    /// Forgets a person's Seerr session on this device and ends it on the server (best effort).
    func signOut(jellyfinUserID: String) {
        guard let serverID = currentServerID else { return }

        endSession(serverID: serverID, jellyfinUserID: jellyfinUserID)
        updateClient()
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

    private func sessionDidChange(serverID: String?) {
        if serverID != loadedServerID {
            load(serverID: serverID)
        } else {
            // Same server, another person: prefer their session for browsing
            if let serverID {
                signedInUserIDs = storedSessionUserIDs(serverID: serverID)
            }
            updateClient()
        }
    }

    private func load(serverID: String?) {
        loadedServerID = serverID
        apiKeyClient = nil
        cachedAnonymousClient = nil
        actingClients = [:]
        sessionClients = [:]
        checkedBrowsingUserIDs = []

        guard let serverID,
              let urlString = Defaults[Self.serverURLKey(serverID: serverID)],
              let url = URL(string: urlString)
        else {
            serverURL = nil
            hasAPIKey = false
            signedInUserIDs = []
            client = nil
            return
        }

        serverURL = SeerrClient.normalizedServerURL(url)

        if let apiKey = keychain.get(Self.apiKeyKeychainKey(serverID: serverID)), apiKey.isEmpty == false {
            apiKeyClient = Self.makeClient(url: url, auth: .apiKey(apiKey, asUser: nil))
        }

        hasAPIKey = apiKeyClient != nil
        signedInUserIDs = storedSessionUserIDs(serverID: serverID)
        client = apiKeyClient ?? preferredSessionClient()

        checkBrowsingSession()
    }

    /// Points `client` at the API key, else at the preferred session. Keeps the same instance when nothing changed.
    private func updateClient() {
        let newClient = apiKeyClient ?? preferredSessionClient()

        if newClient !== client {
            client = newClient
        }

        checkBrowsingSession()
    }

    /// The current user if they are signed in, else any signed-in person.
    private func preferredSessionUserID() -> String? {
        if let currentUserID = Container.shared.currentUserSession()?.user.id,
           signedInUserIDs.contains(currentUserID)
        {
            return currentUserID
        }

        return signedInUserIDs.min()
    }

    /// An unauthenticated client for public endpoints and Quick Connect.
    private func anonymousClient() -> SeerrClient? {
        if let cachedAnonymousClient {
            return cachedAnonymousClient
        }

        guard let serverURL else { return nil }

        let newClient = Self.makeClient(url: serverURL, auth: nil)
        cachedAnonymousClient = newClient
        return newClient
    }

    private func preferredSessionClient() -> SeerrClient? {
        guard let userID = preferredSessionUserID() else { return nil }

        return sessionClient(forJellyfinUserID: userID)
    }

    /// When browsing with a session, checks it once per load and renews it in the background if it expired.
    private func checkBrowsingSession() {
        guard apiKeyClient == nil,
              let userID = preferredSessionUserID(),
              checkedBrowsingUserIDs.contains(userID) == false,
              let browsingClient = sessionClient(forJellyfinUserID: userID)
        else { return }

        checkedBrowsingUserIDs.insert(userID)

        Task { @MainActor [weak self] in
            guard await Self.isSessionExpired(browsingClient) else { return }

            _ = await self?.renewSession(jellyfinUserID: userID)
        }
    }

    private func sessionClient(forJellyfinUserID jellyfinUserID: String) -> SeerrClient? {
        guard signedInUserIDs.contains(jellyfinUserID), let loadedServerID, let serverURL else { return nil }

        if let cachedClient = sessionClients[jellyfinUserID] {
            return cachedClient
        }

        guard let cookie = keychain.get(Self.sessionKeychainKey(serverID: loadedServerID, jellyfinUserID: jellyfinUserID)),
              cookie.isEmpty == false
        else { return nil }

        let sessionClient = Self.makeClient(url: serverURL, auth: .session(cookie: cookie))
        sessionClients[jellyfinUserID] = sessionClient
        return sessionClient
    }

    private func actingClient(asUser seerrUserID: Int, apiKeyClient: SeerrClient) -> SeerrClient? {
        if let cachedClient = actingClients[seerrUserID] {
            return cachedClient
        }

        guard case let .apiKey(apiKey, _)? = apiKeyClient.auth else { return nil }

        let actingClient = Self.makeClient(url: apiKeyClient.baseURL, auth: .apiKey(apiKey, asUser: seerrUserID))
        actingClients[seerrUserID] = actingClient
        return actingClient
    }

    /// Signs the person in again after Seerr rejected their session.
    ///
    /// - Returns: the new session client, or `nil` (the dead session is then forgotten).
    private func renewSession(jellyfinUserID: String) async -> SeerrClient? {
        logger.info(
            "Seerr session expired, signing in again with Quick Connect",
            metadata: ["jellyfinUserID": .string(jellyfinUserID)]
        )

        do {
            try await signInWithQuickConnect(jellyfinUserID: jellyfinUserID)
            return sessionClient(forJellyfinUserID: jellyfinUserID)
        } catch {
            logger.warning(
                "Couldn't renew the Seerr session",
                metadata: [
                    "jellyfinUserID": .string(jellyfinUserID),
                    "error": .string(error.localizedDescription),
                ]
            )

            if let serverID = loadedServerID {
                // The session is dead either way: don't keep sending it
                keychain.delete(Self.sessionKeychainKey(serverID: serverID, jellyfinUserID: jellyfinUserID))
                sessionClients[jellyfinUserID] = nil
                signedInUserIDs.remove(jellyfinUserID)
                updateClient()
            }

            return nil
        }
    }

    private func quickConnectSignIn(jellyfinUserID: String) async throws -> SeerrUser {
        guard let serverID = currentServerID, serverID == loadedServerID, let publicClient = anonymousClient() else {
            throw SeerrError.notConfigured
        }
        guard let memberSession = jellyfinSession(forUserID: jellyfinUserID) else {
            throw ErrorMessage(L10n.SeerrQuickConnect.errorNoJellyfinAccount)
        }

        // 0. Seerr 3.4+
        let serverStatus = try await publicClient.status()

        guard SeerrClient.supportsQuickConnect(version: serverStatus.version) else {
            throw ErrorMessage(L10n.SeerrQuickConnect.unsupportedVersion(serverStatus.version))
        }

        // 1. Seerr asks Jellyfin for a Quick Connect code
        let quickConnect: SeerrQuickConnect

        do {
            quickConnect = try await publicClient.initiateQuickConnect()
        } catch let SeerrError.server(status, message) {
            logger.error(
                "Seerr couldn't start Quick Connect",
                metadata: ["status": .stringConvertible(status)]
            )

            switch status {
            case 403:
                // "Quick Connect is only supported by Jellyfin."
                throw ErrorMessage(message ?? L10n.SeerrQuickConnect.errorQuickConnectDisabled)
            case 404:
                throw ErrorMessage(L10n.SeerrQuickConnect.unsupportedVersion(serverStatus.version))
            default:
                throw ErrorMessage(L10n.SeerrQuickConnect.errorQuickConnectDisabled)
            }
        }

        // 2. The person approves the code with their own Jellyfin session
        do {
            let response = try await memberSession.client.send(Paths.authorizeQuickConnect(code: quickConnect.code))
            let isAuthorized = (try? JSONDecoder().decode(Bool.self, from: response.value)) ?? false

            guard isAuthorized else {
                throw ErrorMessage(L10n.SeerrQuickConnect.errorAuthorizeFailed)
            }
        } catch let error as ErrorMessage {
            throw error
        } catch {
            logger.error(
                "Jellyfin couldn't authorize the Seerr Quick Connect request",
                metadata: ["error": .string(error.localizedDescription)]
            )
            throw ErrorMessage(L10n.SeerrQuickConnect.errorAuthorizeFailed)
        }

        // 3. Seerr turns the approved request into a session
        let signIn = try await authenticate(secret: quickConnect.secret, client: publicClient)

        keychain.set(signIn.cookie, forKey: Self.sessionKeychainKey(serverID: serverID, jellyfinUserID: jellyfinUserID))

        logger.info(
            "Signed in to Seerr with Quick Connect",
            metadata: [
                "jellyfinUserID": .string(jellyfinUserID),
                "seerrUserID": .stringConvertible(signIn.user.id),
            ]
        )

        if loadedServerID == serverID {
            sessionClients[jellyfinUserID] = nil
            checkedBrowsingUserIDs.insert(jellyfinUserID)
            signedInUserIDs.insert(jellyfinUserID)

            // Without an API key, a new or renewed session may become the browsing client
            updateClient()
        }

        return signIn.user
    }

    /// Step 3, retried once: Jellyfin may need a moment to mark the request as authorized.
    private func authenticate(secret: String, client publicClient: SeerrClient) async throws -> SeerrSignIn {
        do {
            return try await publicClient.authenticateQuickConnect(secret: secret)
        } catch SeerrError.unauthorized {
            try await Task.sleep(nanoseconds: 1_000_000_000)
        } catch {
            throw Self.signInError(error)
        }

        do {
            return try await publicClient.authenticateQuickConnect(secret: secret)
        } catch {
            throw Self.signInError(error)
        }
    }

    /// Readable errors for `authenticateQuickConnect(secret:)`.
    private static func signInError(_ error: Error) -> Error {
        switch error {
        case SeerrError.unauthorized:
            // `INVALID_CREDENTIALS`: the request wasn't (yet) authorized
            return ErrorMessage(L10n.SeerrQuickConnect.errorAuthorizeFailed)

        case let SeerrError.server(status, message) where status == 403:
            // "Access denied.": not imported and new Jellyfin sign-in is off
            if let message, message != "Access denied." {
                return ErrorMessage(message)
            }
            return ErrorMessage(L10n.SeerrQuickConnect.errorAccessDenied)

        default:
            return error
        }
    }

    /// Forgets a session locally, then ends it on the server in the background.
    private func endSession(serverID: String, jellyfinUserID: String) {
        let key = Self.sessionKeychainKey(serverID: serverID, jellyfinUserID: jellyfinUserID)

        if let cookie = keychain.get(key), cookie.isEmpty == false, let serverURL {
            let endingClient = sessionClients[jellyfinUserID] ?? Self.makeClient(url: serverURL, auth: .session(cookie: cookie))

            Task {
                _ = try? await endingClient.signOut()
            }
        }

        keychain.delete(key)
        sessionClients[jellyfinUserID] = nil
        checkedBrowsingUserIDs.remove(jellyfinUserID)
        signedInUserIDs.remove(jellyfinUserID)
    }

    /// Sessions belong to one Seerr server: when the saved URL changes, end them (on the old server)
    /// and forget them, so a session cookie is never sent to another server.
    private func endSessionsIfServerURLChanged(serverID: String, newURL: URL) {
        guard let storedURLString = Defaults[Self.serverURLKey(serverID: serverID)],
              let storedURL = URL(string: storedURLString),
              SeerrClient.normalizedServerURL(storedURL) != newURL
        else { return }

        for userID in storedUserIDs(serverID: serverID).union(signedInUserIDs) {
            endSession(serverID: serverID, jellyfinUserID: userID)
        }
    }

    /// A Jellyfin session for this user on the current server: the current session, or a
    /// household session built from their stored access token.
    private func jellyfinSession(forUserID userID: String) -> UserSession? {
        Container.shared
            .currentUserSession()?
            .householdSessions()
            .first { $0.user.id == userID }
    }

    private func storedUserIDs(serverID: String) -> Set<String> {
        Set(
            StoredValues[.User.users]
                .filter { $0.serverID == serverID }
                .map(\.id)
        )
    }

    private func storedSessionUserIDs(serverID: String) -> Set<String> {
        storedUserIDs(serverID: serverID).filter { userID in
            let cookie = keychain.get(Self.sessionKeychainKey(serverID: serverID, jellyfinUserID: userID))
            return cookie?.isEmpty == false
        }
    }

    private static func isSessionExpired(_ client: SeerrClient) async -> Bool {
        do {
            _ = try await client.me()
            return false
        } catch SeerrError.unauthorized {
            return true
        } catch {
            return false
        }
    }

    private static func isValidServerURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }

        return (scheme == "http" || scheme == "https") && url.host != nil
    }

    private static func makeClient(url: URL, auth: SeerrClient.AuthMode?) -> SeerrClient {
        SeerrClient(
            baseURL: url,
            auth: auth,
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

    /// One Seerr session (`connect.sid`) per Jellyfin user and server.
    private static func sessionKeychainKey(serverID: String, jellyfinUserID: String) -> String {
        "seerrSession-\(serverID)-\(jellyfinUserID)"
    }
}

// MARK: - NetworkLogger

extension NetworkLogger {

    /// A Pulse network logger for Seerr that redacts the admin API key, session cookies
    /// and Quick Connect secrets.
    static func seerr() -> NetworkLogger {
        var configuration = NetworkLogger.Configuration()
        // Pulse 5.2.3 drops its `.caseInsensitive` option for these patterns, so list each casing
        configuration.sensitiveHeaders = [
            "X-Api-Key", "x-api-key", "X-API-Key", "X-API-KEY",
            "Cookie", "cookie", "COOKIE",
            "Set-Cookie", "set-cookie", "Set-cookie", "SET-COOKIE",
        ]
        configuration.sensitiveQueryItems = ["secret"]
        configuration.sensitiveDataFields = ["apiKey", "password", "plexToken", "jellyfinAuthToken", "secret"]
        return NetworkLogger(configuration: configuration)
    }
}
