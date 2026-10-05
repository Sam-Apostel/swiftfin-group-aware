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
import Get
import JellyfinAPI

@MainActor
@Stateful
final class QuickConnectAuthorizeViewModel: ViewModel {

    @CasePathable
    enum Action {
        case authorize(code: String)
        case cancel

        var transition: Transition {
            switch self {
            case .authorize: .loop(.authorizing)
            case .cancel: .to(.initial)
            }
        }
    }

    enum Event {
        case authorized
        case error
    }

    enum State {
        case authorizing
        case initial
    }

    /// The user the other device signs in as.
    @Published
    private(set) var user: UserDto

    /// The household sessions to choose from in "Sign in as".
    ///
    /// Only for the current session user (Settings › your name › Quick Connect) with more than one
    /// account on this device. Empty on the admin path (another user's details): no chooser there.
    @Published
    private(set) var householdSessions: [UserSession] = []

    /// The session chosen in "Sign in as". Each person authorizes with their own token,
    /// because Jellyfin only accepts another user's id from an admin.
    private var chosenSession: UserSession?

    init(user: UserDto) {
        self.user = user
        super.init()

        guard let userSession, user.id == userSession.user.id else { return }

        let sessions = userSession.householdSessions()

        guard sessions.count > 1 else { return }

        householdSessions = sessions

        if let defaultSession = Self.defaultSession(in: sessions, current: userSession) {
            select(session: defaultSession)
        }
    }

    /// Whether to show the "Sign in as" chooser.
    var isChoosingPerson: Bool {
        householdSessions.count > 1
    }

    /// The Jellyfin user id of the person the other device signs in as.
    var chosenUserID: String? {
        chosenSession?.user.id ?? user.id
    }

    /// Who the other device signs in as: the chosen person, with their own session.
    func select(session: UserSession) {
        chosenSession = session
        userSession = session
        user = session.user.data
    }

    @Function(\Action.Cases.authorize)
    private func _authorize(_ code: String) async throws {

        let response: Response<Data>

        if let chosenSession {
            // Sent with the chosen person's own token, for their own user id
            let request = Paths.authorizeQuickConnect(code: code, userID: chosenSession.user.id)
            response = try await chosenSession.client.send(request)
        } else {
            guard let userID = user.id else {
                logger.critical("User ID is nil")
                throw ErrorMessage(L10n.unknownError)
            }

            let request = Paths.authorizeQuickConnect(code: code, userID: userID)
            response = try await send(request)
        }

        let decoder = JSONDecoder()
        let isAuthorized = (try? decoder.decode(Bool.self, from: response.value)) ?? false

        guard isAuthorized else {
            throw ErrorMessage("Authorization unsuccessful")
        }

        events.send(.authorized)
    }

    // MARK: - Default Person

    /// The first grown-up on the couch in pick order, else the first grown-up stored on this device.
    /// Never a child while a grown-up is there.
    private static func defaultSession(in sessions: [UserSession], current: UserSession) -> UserSession? {
        let pickOrderedIDs = Container.shared.userSessionManager().pickOrderedMemberIDs(of: current.couch)

        let couchSessions = pickOrderedIDs.compactMap { id in
            sessions.first { $0.user.id == id }
        }
        let otherSessions = sessions.filter { session in
            !pickOrderedIDs.contains(session.user.id)
        }
        let candidates = couchSessions + otherSessions

        return candidates.first { !$0.user.isRestricted }
            ?? candidates.first { !$0.user.isChildAudience }
            ?? candidates.first
    }
}
