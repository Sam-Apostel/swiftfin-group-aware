//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import Foundation
import OrderedCollections

@MainActor
@Stateful
final class SelectUserViewModel: ViewModel {

    @CasePathable
    enum Action {
        case deleteUsers(Set<UserState>)
        case error
        case getServers
        case signIn(UserState, pin: String)

        var transition: Transition {
            switch self {
            case .getServers:
                .to(.loading, then: .content)
                    .whenBackground(.refreshing)

            case .deleteUsers:
                .background(.refreshing)

            case .error, .signIn:
                .none
            }
        }
    }

    enum BackgroundState {
        case refreshing
    }

    enum Event {
        case error
        case signedIn(UserState)
    }

    enum State {
        case initial
        case loading
        case content
    }

    @Published
    private(set) var servers: OrderedDictionary<ServerState, [UserState]> = [:]

    @Function(\Action.Cases.deleteUsers)
    private func _deleteUsers(_ users: Set<UserState>) async throws {
        for user in users {
            try user.delete()
        }

        try await _getServers()
    }

    @Function(\Action.Cases.getServers)
    private func _getServers() async throws {
        let usersByServerID = StoredValues[.User.users]
            .reduce(into: [String: [UserState]]()) { partialResult, user in
                partialResult[user.serverID, default: []].append(user)
            }

        servers = StoredValues[.Server.servers]
            .sorted(using: \.name)
            .reduce(into: .init()) { partialResult, server in
                partialResult[server] = usersByServerID[server.id, default: []]
                    .sorted(using: \.username)
            }
    }

    @Function(\Action.Cases.signIn)
    private func _signIn(_ user: UserState, _ pin: String) throws {
        try validatePin(pin, for: user)

        events.send(.signedIn(user))
    }

    /// Checks the PIN entered for a user that requires one.
    ///
    /// The same rule as `CouchMemberAuthenticator.isValidPin(_:for:)`, which confirms
    /// each member when starting a couch.
    func validatePin(_ pin: String, for user: UserState) throws {
        guard CouchMemberAuthenticator.isValidPin(pin, for: user) else {
            throw ErrorMessage(L10n.incorrectPinForUser(user.username))
        }
    }
}
