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

extension Container {

    var userSessionManager: Factory<UserSessionManager> {
        self { UserSessionManager() }
            .singleton
    }

    var currentUserSession: Factory<UserSession?> {
        self { self.userSessionManager().currentSession }
            .cached
    }
}

final class UserSessionManager: ObservableObject {

    enum State: Equatable {
        case initial
        case signedOut
        case signedIn
    }

    enum SignOutReason {
        case backgroundTimeout
        case explicit
    }

    enum AuthenticationError: Error {
        case missingAuthenticationAction
    }

    @Injected(\.keychainService)
    private var keychain: CouchfinKeychain

    @Published
    private(set) var state: State = .initial

    @Published
    private(set) var currentSession: UserSession?

    @Published
    private(set) var pendingDeepLink: DeepLink?

    let routePublisher = PassthroughSubject<NavigationRoute, Never>()

    var cancellables = Set<AnyCancellable>()

    let logger = Logger.swiftfin()

    private(set) var mediaPlayerManager: MediaPlayerManager?

    @MainActor
    var hasActivePlayback: Bool {
        guard let mediaPlayerManager else { return false }

        return mediaPlayerManager.state != .stopped
    }

    init() {
        setupObservations()
    }

    @MainActor
    func start() async {
        guard state == .initial else { return }

        do {
            #if os(tvOS)
            // servers and people are shared by every Apple TV profile;
            // a profile switch puts that profile's default person on the couch
            HouseholdStore.restore()
            AppleTVProfile.prepareLaunch()
            #endif

            if Defaults[.signOutOnClose] {
                Defaults[.lastSignedInUserID] = .signedOut
                Defaults[.Couch.memberIDs] = []
            }

            try await updateCurrentSession(with: resolveStoredSession())
        } catch {
            logger.error(
                "Unable to restore launch session",
                metadata: ["error": .string(error.localizedDescription)]
            )

            await updateCurrentSession(with: nil)
        }
    }

    @MainActor
    private func refreshCurrentSession() async {
        do {
            try await updateCurrentSession(with: resolveStoredSession())
        } catch {
            logger.error(
                "Unable to refresh current user session",
                metadata: ["error": .string(error.localizedDescription)]
            )
            await updateCurrentSession(with: nil)
        }
    }

    /// Signs in a single user, as a couch of one.
    @MainActor
    func signIn(userID: String) async throws {
        try await signIn(userIDs: [userID])
    }

    /// Signs in everyone on the couch, in the order they were picked.
    ///
    /// Users that are not stored, are on another server than the first
    /// picked user, or have no stored access token are dropped. The primary
    /// user is the first picked user, unless kid-safe browsing is enabled
    /// and a member is restricted: then the most restricted member is the primary.
    @MainActor
    func signIn(userIDs: [String]) async throws {
        let members = couchMembers(
            for: userIDs,
            in: StoredValues[.User.users]
        )

        if let primary = couchPrimary(of: members) {
            let otherMemberIDs = members.map(\.id).filter { $0 != primary.id }

            #if os(tvOS)
            AppleTVProfile.didStartCouch(memberIDs: members.map(\.id))
            #endif

            Defaults[.Couch.memberIDs] = [primary.id] + otherMemberIDs
            Defaults[.Couch.lastMemberIDs] = members.map(\.id)
            Defaults[.lastSignedInUserID] = .signedIn(userID: primary.id)
        } else {
            // No usable couch members, keep the single user sign in behavior
            guard let userID = userIDs.first else {
                throw UserSessionError.missingCurrentSession
            }

            Defaults[.Couch.memberIDs] = []
            Defaults[.lastSignedInUserID] = .signedIn(userID: userID)
        }

        try await updateCurrentSession(with: resolveStoredSession())

        Task {
            await refreshServerInformationIfNeeded(reason: .explicitSignIn)
        }
    }

    @MainActor
    func signOut(reason: SignOutReason) async {
        guard currentSession != nil else { return }

        Defaults[.lastSignedInUserID] = .signedOut
        Defaults[.Couch.memberIDs] = []
        #if os(tvOS)
        TopShelfPublisher.clear()
        #endif
        await refreshCurrentSession()

        logger.info(
            "Signed out current user",
            metadata: ["reason": .string(String(describing: reason))]
        )
    }

    @MainActor
    private func stopActivePlayback() async {
        await mediaPlayerManager?.stop()
        self.mediaPlayerManager = nil
    }

    @MainActor
    func scheduleServerConnectionResolution() {
        currentSession?.serverConnectionManager.scheduleConnectionResolution()
    }

    @MainActor
    func handleOpenURL(
        _ url: URL,
        authenticationAction: LocalUserAuthenticationAction
    ) async {
        guard let deepLink = DeepLink(url) else { return }

        do {
            let deepLinkSession = try session(for: deepLink)
            let currentSession = currentSession
            let isSameServer = currentSession?.server.id == deepLinkSession.server.id
            let currentMemberIDs = currentSession?.couch.memberIDs ?? []

            // A link for a couch (from the Top Shelf) puts exactly those people on the couch.
            // A link for one person keeps the current couch when they're already on it.
            let isSameCouch: Bool = if let couchMemberIDs = deepLink.couchMemberIDs {
                isSameServer && Set(couchMemberIDs) == currentMemberIDs
            } else {
                isSameServer && currentMemberIDs.contains(deepLinkSession.user.id)
            }

            if !isSameCouch {
                try await authenticate(
                    user: deepLinkSession.user,
                    authenticationAction: authenticationAction
                )

                if hasActivePlayback {
                    await stopActivePlayback()
                }

                try await signIn(userIDs: deepLink.couchMemberIDs ?? [deepLinkSession.user.id])
            }

            pendingDeepLink = deepLink
        } catch {
            logger.error(
                "Failed to process deep link",
                metadata: ["error": .string(error.localizedDescription)]
            )
        }
    }

    @MainActor
    func consumePendingDeepLink() -> DeepLink? {
        defer {
            pendingDeepLink = nil
        }

        return pendingDeepLink
    }

    @MainActor
    func appDidEnterBackground() {
        Defaults[.backgroundTimeStamp] = Date.now
    }

    @MainActor
    func appWillEnterForeground() async {
        await refreshCurrentSession()

        Task {
            await refreshServerInformationIfNeeded(reason: .stale)
        }

        guard currentSession != nil else { return }
        guard Defaults[.signOutOnBackground] else { return }
        guard !hasActivePlayback else { return }

        let backgroundedInterval = Date.now.timeIntervalSince(Defaults[.backgroundTimeStamp])
        if backgroundedInterval > Defaults[.backgroundSignOutInterval] {
            await signOut(reason: .backgroundTimeout)
        }
    }

    private enum ServerInformationRefreshReason {
        case explicitSignIn
        case stale
    }

    private func session(for deepLink: DeepLink) throws -> (server: ServerState, user: UserState) {
        guard let server = StoredValues[.Server.servers].first(where: { $0.id == deepLink.serverID }) else {
            throw DeepLinkError.missingServer(deepLink.serverID)
        }
        guard let user = StoredValues[.User.users].first(where: { $0.id == deepLink.userID && $0.serverID == server.id }) else {
            throw DeepLinkError.missingUser(deepLink.userID)
        }

        return (server, user)
    }

    private func authenticate(
        user: UserState,
        authenticationAction: LocalUserAuthenticationAction
    ) async throws {
        guard user.accessPolicy != .none else { return }

        let evaluatedPolicy = try await authenticationAction(
            policy: user.accessPolicy,
            reason: user.accessPolicy.authenticateReason(user: user)
        )

        guard let pinPolicy = evaluatedPolicy as? PinEvaluatedUserAccessPolicy else { return }

        if let storedPin = keychain.get("\(user.id)-pin") {
            guard pinPolicy.pin == storedPin else {
                throw ErrorMessage(L10n.incorrectPinForUser(user.username))
            }
        }
    }

    @MainActor
    private func refreshServerInformationIfNeeded(reason: ServerInformationRefreshReason) async {
        guard let currentSession else { return }

        switch reason {
        case .explicitSignIn:
            break
        case .stale:
            guard Defaults[.lastServerInformationRefreshDate].isStale(with: .hours(24)) else { return }
        }

        do {
            try await currentSession.server.updateServerInfo()
            try await currentSession.user.updateUserData(server: currentSession.server)

            Defaults[.lastServerInformationRefreshDate] = Date.now
        } catch {
            logger.error(
                "Unable to refresh server and user information",
                metadata: ["error": .string(error.localizedDescription)]
            )
        }

        // Keep the other couch members' policies fresh
        for member in currentSession.couch.otherMembers where member.storedAccessToken != nil {
            do {
                try await member.updateUserData(server: currentSession.server)
            } catch {
                logger.error(
                    "Unable to refresh couch member information",
                    metadata: ["error": .string(error.localizedDescription)]
                )
            }
        }
    }

    private func setupObservations() {
        Notifications[.applicationDidEnterBackground]
            .publisher
            .sink { [weak self] in
                Task { @MainActor in
                    self?.appDidEnterBackground()
                }
            }
            .store(in: &cancellables)

        Notifications[.applicationWillEnterForeground]
            .publisher
            .sink { [weak self] in
                Task { @MainActor in
                    await self?.appWillEnterForeground()
                }
            }
            .store(in: &cancellables)

        Container.shared
            .mediaPlayerManagerPublisher()
            .sink { [weak self] manager in
                Task { @MainActor in
                    self?.mediaPlayerManager = manager
                }
            }
            .store(in: &cancellables)

        observeSocketCommands()
    }

    @MainActor
    private func updateCurrentSession(with newSession: UserSession?) async {
        let previousSession = currentSession

        previousSession?.willStop()
        await newSession?.willStart()

        currentSession = newSession
        Container.shared.currentUserSession.reset()

        let didChangeServer = previousSession?.server.id != newSession?.server.id
        let didChangeUser = previousSession?.user.id != newSession?.user.id
        let didChangeCouch = previousSession?.couch.id != newSession?.couch.id

        if didChangeServer || didChangeUser || didChangeCouch {
            Container.shared.mediaPlayerManager.reset()
        }

        if newSession == nil {
            state = .signedOut
        } else {
            state = .signedIn
        }

        newSession?.didStart()

        Notifications[.didChangeCouch].post(newSession?.couch.members.map(\.id) ?? [])
    }

    private func resolveStoredSession() throws -> UserSession? {
        guard case let .signedIn(userId) = Defaults[.lastSignedInUserID] else { return nil }

        let storedUsers = StoredValues[.User.users]

        guard let user = storedUsers.first(where: { $0.id == userId }) else {
            Defaults[.lastSignedInUserID] = .signedOut
            Defaults[.Couch.memberIDs] = []
            throw UserSessionError.invalidStoredSession(userID: userId)
        }
        guard let server = StoredValues[.Server.servers].first(where: { $0.id == user.serverID }) else {
            Defaults[.lastSignedInUserID] = .signedOut
            Defaults[.Couch.memberIDs] = []
            throw UserSessionError.invalidStoredSession(userID: userId)
        }

        return .init(
            server: server,
            user: user,
            couch: storedCouch(primary: user, in: storedUsers)
        )
    }
}

// MARK: - Couch

extension UserSessionManager {

    /// The stored users for the given IDs, in order, that can be on the same couch.
    ///
    /// Drops IDs that are not stored users, are on another server than the
    /// first stored user, have no stored access token, or are duplicates.
    private func couchMembers(for userIDs: [String], in storedUsers: [UserState]) -> [UserState] {
        var couchServerID: String?
        var seenIDs: Set<String> = []
        var members: [UserState] = []

        for userID in userIDs {
            guard let user = storedUsers.first(where: { $0.id == userID }) else { continue }

            let serverID = couchServerID ?? user.serverID
            couchServerID = serverID

            guard user.serverID == serverID,
                  user.storedAccessToken != nil,
                  seenIDs.insert(user.id).inserted
            else { continue }

            members.append(user)
        }

        return members
    }

    /// The member the app should browse as.
    ///
    /// The first member, unless kid-safe browsing is enabled and a member
    /// is restricted: then the most restricted member.
    private func couchPrimary(of members: [UserState]) -> UserState? {
        guard let firstMember = members.first else { return nil }
        guard members.count > 1, Defaults[.Couch.kidSafeBrowsing] else { return firstMember }
        guard members.contains(where: \.isRestricted) else { return firstMember }

        return members.min { $0.restrictionScore < $1.restrictionScore } ?? firstMember
    }

    /// Rebuilds the current couch from `Defaults[.Couch.memberIDs]`,
    /// with the given primary user first.
    ///
    /// Falls back to a couch of only the primary user when the stored
    /// members don't belong to the primary user.
    private func storedCouch(primary: UserState, in storedUsers: [UserState]) -> CouchGroup {
        let memberIDs = Defaults[.Couch.memberIDs]

        guard memberIDs.contains(primary.id) else { return .solo(primary) }

        let members = couchMembers(
            for: [primary.id] + memberIDs,
            in: storedUsers
        )

        return CouchGroup(
            primary: primary,
            members: members
        )
    }
}
