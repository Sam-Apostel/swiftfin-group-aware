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
    private var keychain: KeychainSwift

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
            if Defaults[.signOutOnClose] {
                Defaults[.lastSignedInUserID] = .signedOut
                Defaults[.Couch.memberIDs] = []
            }

            try await updateCurrentSession(with: resolveStoredSession())

            // A restored couch keeps its stored primary: on a cold launch (no foreground
            // notification) sync the kid flags too, so it turns stricter by itself
            if currentSession != nil {
                Task { @MainActor [weak self] in
                    await self?.refreshKidsAndApplyStricterPrimary()
                }
            }
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
    ///
    /// The household kid flags are synced first (at most about 1.5 s, otherwise the
    /// cached flags are used), so a kid marked on another device is a kid here.
    ///
    /// - Important: to sign in an existing couch again, pass `pickOrderedMemberIDs(of:)`,
    ///   so the pick order is kept and a kid never becomes the first pick.
    @MainActor
    func signIn(userIDs: [String]) async throws {
        try await signIn(userIDs: userIDs, refreshingKids: true)
    }

    /// `signIn(userIDs:)`, optionally without the bounded kids refresh first.
    ///
    /// `applyStricterPrimaryIfNeeded()` passes `false`: it has just checked the fresh flags
    /// and that nothing is playing, so it must switch right away (no network wait in between,
    /// during which playback could start and then be torn down by the session change).
    @MainActor
    private func signIn(userIDs: [String], refreshingKids: Bool) async throws {
        if refreshingKids {
            await refreshKidsBeforeSignIn(userIDs: userIDs)
        }

        let members = couchMembers(
            for: userIDs,
            in: StoredValues[.User.users]
        )

        if let primary = couchPrimary(of: members) {
            let otherMemberIDs = members.map(\.id).filter { $0 != primary.id }

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
            let isSameUserSession = currentSession?.server.id == deepLinkSession.server.id && currentSession?.user.id == deepLinkSession
                .user.id

            if !isSameUserSession {
                try await authenticate(
                    user: deepLinkSession.user,
                    authenticationAction: authenticationAction
                )

                if hasActivePlayback {
                    await stopActivePlayback()
                }

                try await signIn(userID: deepLinkSession.user.id)
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

        if Defaults[.signOutOnBackground], !hasActivePlayback {
            let backgroundedInterval = Date.now.timeIntervalSince(Defaults[.backgroundTimeStamp])
            if backgroundedInterval > Defaults[.backgroundSignOutInterval] {
                await signOut(reason: .backgroundTimeout)
            }
        }

        // Only while still signed in
        await refreshKidsAndApplyStricterPrimary()
    }

    /// Refreshes the members' user data and the household kid flags when the last kids refresh
    /// is older than 10 minutes, then makes the couch stricter if needed. Does nothing while signed out.
    @MainActor
    private func refreshKidsAndApplyStricterPrimary() async {
        guard let currentSession else { return }

        if Container.shared.couchKidsStore().lastRefreshDate?.isStale(with: .minutes(10)) ?? true {
            await refreshKidsAndMembers(of: currentSession)
        }

        await applyStricterPrimaryIfNeeded()
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

        // Keep the other couch members' policies fresh (fetched concurrently, applied in order), then the kid flags
        await UserState.refreshUserData(currentSession.couch.otherMembers, server: currentSession.server)
        await Container.shared.couchKidsStore().refresh(
            server: currentSession.server,
            users: storedUsers(on: currentSession.server)
        )
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
    ///
    /// - Parameters:
    ///   - userIDs: the user ids in pick order.
    ///   - storedUsers: usually `StoredValues[.User.users]`.
    func couchMembers(for userIDs: [String], in storedUsers: [UserState]) -> [UserState] {
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
    /// is restricted: then the most restricted member (lowest `restrictionScore`).
    ///
    /// - Parameter members: the couch members in pick order (see `pickOrderedMemberIDs(of:)`).
    /// - Returns: `nil` for no members.
    func couchPrimary(of members: [UserState]) -> UserState? {
        guard let firstMember = members.first else { return nil }
        guard members.count > 1, Defaults[.Couch.kidSafeBrowsing] else { return firstMember }
        guard members.contains(where: \.isRestricted) else { return firstMember }

        return members.min { $0.restrictionScore < $1.restrictionScore } ?? firstMember
    }

    /// The member ids of `couch` in the order they were picked:
    /// `Defaults[.Couch.lastMemberIDs]` filtered to the couch, then any missing members in couch order.
    ///
    /// Every re-sign-in of an existing couch must pass this order to `signIn(userIDs:)`.
    /// `CouchGroup.members` puts the primary first, so passing those would make the
    /// primary (e.g. the kid) the first pick.
    func pickOrderedMemberIDs(of couch: CouchGroup) -> [String] {
        let couchMemberIDs = couch.memberIDs
        var seenIDs: Set<String> = []
        var orderedIDs: [String] = []

        for userID in Defaults[.Couch.lastMemberIDs] where couchMemberIDs.contains(userID) {
            guard seenIDs.insert(userID).inserted else { continue }

            orderedIDs.append(userID)
        }

        for member in couch.members where seenIDs.insert(member.id).inserted {
            orderedIDs.append(member.id)
        }

        return orderedIDs
    }

    /// Makes the current couch browse as a stricter member when one appeared,
    /// e.g. a kid flag synced from another device or an age limit added on the server.
    ///
    /// Only acts on a group couch without active playback. Recomputes `couchPrimary(of:)`
    /// over the stored members in pick order, and signs in again (keeping the pick order)
    /// only when that member has a lower `restrictionScore` than the current primary.
    /// It never makes browsing less strict.
    ///
    /// - Returns: whether the couch was signed in again.
    @MainActor
    @discardableResult
    func applyStricterPrimaryIfNeeded() async -> Bool {
        guard let currentSession, currentSession.couch.isGroup else { return false }
        guard !hasActivePlayback else { return false }

        let orderedIDs = pickOrderedMemberIDs(of: currentSession.couch)
        let members = couchMembers(for: orderedIDs, in: StoredValues[.User.users])

        guard let stricterPrimary = couchPrimary(of: members),
              stricterPrimary.id != currentSession.user.id,
              stricterPrimary.restrictionScore < currentSession.user.restrictionScore
        else { return false }

        logger.info(
            "Couch: browsing as a stricter member",
            metadata: [
                "from": .string(currentSession.user.id),
                "to": .string(stricterPrimary.id),
            ]
        )

        do {
            // No kids refresh in between: the flags were just read and nothing is playing right now
            try await signIn(userIDs: orderedIDs, refreshingKids: false)
            return true
        } catch {
            logger.error(
                "Unable to switch the couch to a stricter member",
                metadata: ["error": .string(error.localizedDescription)]
            )
            return false
        }
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

// MARK: - Kids

extension UserSessionManager {

    /// How long a sign-in waits for the household kid flags before using the cached ones.
    private static let kidsRefreshTimeout: Duration = .milliseconds(1500)

    /// The stored users of a server.
    private func storedUsers(on server: ServerState) -> [UserState] {
        StoredValues[.User.users].filter { $0.serverID == server.id }
    }

    /// Syncs the kid flags of the first picked user's server, bounded to `kidsRefreshTimeout`.
    ///
    /// On timeout the sign-in continues with the cached flags; the refresh finishes in the
    /// background and then makes the couch stricter if a kid flag arrived.
    @MainActor
    private func refreshKidsBeforeSignIn(userIDs: [String]) async {
        let storedUsers = StoredValues[.User.users]

        guard let firstUser = userIDs.lazy.compactMap({ userID in storedUsers.first { $0.id == userID } }).first,
              let server = StoredValues[.Server.servers].first(where: { $0.id == firstUser.serverID })
        else { return }

        let serverUsers = storedUsers.filter { $0.serverID == server.id }
        let kidsStore = Container.shared.couchKidsStore()

        let refreshTask = Task { @MainActor in
            await kidsStore.refresh(server: server, users: serverUsers)
        }

        let didFinish = await Self.waitForTask(refreshTask, timeout: Self.kidsRefreshTimeout)

        guard !didFinish else { return }

        logger.warning("Kid flags: refresh is slow, signing in with the cached flags")

        Task { @MainActor [weak self] in
            await refreshTask.value
            await self?.applyStricterPrimaryIfNeeded()
        }
    }

    /// Refreshes the user data of the couch members and the household kid flags.
    @MainActor
    private func refreshKidsAndMembers(of session: UserSession) async {
        await UserState.refreshUserData(session.couch.members, server: session.server)
        await Container.shared.couchKidsStore().refresh(
            server: session.server,
            users: storedUsers(on: session.server)
        )
    }

    /// Waits for `task` at most `timeout`. The task itself is never cancelled.
    ///
    /// - Returns: whether the task finished in time.
    @MainActor
    private static func waitForTask(_ task: Task<Void, Never>, timeout: Duration) async -> Bool {
        let race = CouchTaskRace()

        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            race.continuation = continuation

            Task { @MainActor in
                await task.value
                race.finish(true)
            }

            Task { @MainActor in
                try? await Task.sleep(for: timeout)
                race.finish(false)
            }
        }
    }
}

/// Resumes a continuation once, with the result of whichever side finishes first. Main actor only.
@MainActor
private final class CouchTaskRace {

    var continuation: CheckedContinuation<Bool, Never>?

    func finish(_ result: Bool) {
        guard let continuation else { return }

        self.continuation = nil
        continuation.resume(returning: result)
    }
}
