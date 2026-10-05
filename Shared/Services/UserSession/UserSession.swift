//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI
import Pulse

final class UserSession {

    let server: ServerState
    let user: UserState

    /// Everyone on the couch for this session. `user` is the couch's primary user.
    let couch: CouchGroup

    /// Whether this is an inert session for a couch or household member.
    ///
    /// Member sessions are never started: they only provide an authenticated
    /// `client` for that member, which uses its own device ID so its calls
    /// never take over the primary user's server session.
    let isCouchMember: Bool

    lazy var client: JellyfinClient = JellyfinClient(
        configuration: .swiftfinConfiguration(
            url: server.effectiveServerURL,
            accessToken: isCouchMember ? user.storedAccessToken : user.accessToken,
            deviceIDSuffix: isCouchMember ? String(user.id.prefix(8)) : nil
        ),
        sessionConfiguration: .swiftfin,
        sessionDelegate: URLSessionProxyDelegate(logger: NetworkLogger.swiftfin())
    )

    /// Inert sessions for the other couch members that have a stored access token.
    ///
    /// These are never started.
    lazy var memberSessions: [UserSession] = couch
        .otherMembers
        .filter { $0.storedAccessToken != nil }
        .map { member in
            UserSession(
                server: server,
                user: member,
                couch: nil,
                isCouchMember: true
            )
        }

    @MainActor
    lazy var serverConnectionManager = ServerConnectionManager()

    lazy var serverSocketManager = ServerSocketManager()

    @MainActor
    lazy var couchPlaybackService = CouchPlaybackService()

    @MainActor
    private lazy var services: [any UserSessionService] = [
        serverConnectionManager,
        serverSocketManager,
        couchPlaybackService,
    ]

    private let householdLock = NSLock()
    private var householdSessionsCache: [String: UserSession] = [:]

    init(
        server: ServerState,
        user: UserState,
        couch: CouchGroup? = nil,
        isCouchMember: Bool = false
    ) {
        self.server = server
        self.user = user
        self.couch = couch ?? .solo(user)
        self.isCouchMember = isCouchMember
    }

    /// The session for the given couch member: `self` for the primary
    /// user, otherwise the matching inert member session.
    func session(forMemberID id: String) -> UserSession? {
        if id == user.id {
            return self
        }

        return memberSessions.first { $0.user.id == id }
    }

    /// This session plus an inert session for every other stored user on this
    /// server that has a stored access token, whether or not they are on the couch.
    ///
    /// Couch members reuse their `memberSessions`. Reads stored users, so call
    /// this from the main thread.
    func householdSessions() -> [UserSession] {
        let householdUsers = StoredValues[.User.users]
            .filter { $0.serverID == server.id && $0.id != user.id }
        let couchMemberSessions = self.memberSessions

        householdLock.lock()
        defer { householdLock.unlock() }

        var sessions: [UserSession] = [self]

        for householdUser in householdUsers {
            if let memberSession = couchMemberSessions.first(where: { $0.user.id == householdUser.id }) {
                sessions.append(memberSession)
                continue
            }

            if let cachedSession = householdSessionsCache[householdUser.id] {
                sessions.append(cachedSession)
                continue
            }

            guard householdUser.storedAccessToken != nil else { continue }

            let householdSession = UserSession(
                server: server,
                user: householdUser,
                couch: nil,
                isCouchMember: true
            )

            householdSessionsCache[householdUser.id] = householdSession
            sessions.append(householdSession)
        }

        return sessions
    }

    @MainActor
    func willStart() async {
        for service in services {
            await service.willStart(userSession: self)
        }
    }

    @MainActor
    func didStart() {
        for service in services {
            service.didStart(userSession: self)
        }
    }

    @MainActor
    func willStop() {
        for service in services.reversed() {
            service.willStop(userSession: self)
        }
    }
}
