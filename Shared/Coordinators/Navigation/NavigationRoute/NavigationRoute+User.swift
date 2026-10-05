//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

extension NavigationRoute {

    static var connectToServer: NavigationRoute {
        NavigationRoute(
            id: "connectToServer",
            style: .sheet
        ) {
            ConnectToServerView()
        }
    }

    static func quickConnect(client: JellyfinClient, action: @escaping (String) async -> Void) -> NavigationRoute {
        NavigationRoute(
            id: "quickConnectView",
            style: .sheet
        ) {
            QuickConnectView(client: client, action: action)
        }
    }

    #if os(iOS)
    // TODO: rename to `localUserAccessPolicy`
    static func userSecurity(pinHint: Binding<String>, accessPolicy: Binding<LocalUserAccessPolicy>) -> NavigationRoute {
        NavigationRoute(
            id: "userSecurity",
            style: .sheet
        ) {
            LocalUserAccessPolicyView(
                pinHint: pinHint,
                accessPolicy: accessPolicy
            )
        }
    }
    #endif

    /// Signs a user in to `server` and saves them on this device, then posts
    /// `Notifications[.didAddUser]` and dismisses. It never starts a session.
    ///
    /// - Parameter username: Fills in the username, e.g. to sign a stored user in again.
    static func userSignIn(server: ServerState, username: String? = nil) -> NavigationRoute {
        NavigationRoute(
            id: "userSignIn",
            style: .sheet
        ) {
            WithLocalUserAuthentication {
                UserSignInView(server: server, username: username)
            }
        }
    }
}
