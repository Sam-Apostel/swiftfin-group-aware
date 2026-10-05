//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension NavigationRoute {

    /// "Who's on the couch?" while signed in: add or take people off the couch without signing anyone out.
    ///
    /// A sheet on iOS and a full-screen cover on tvOS. New people confirm with their PIN, and a change
    /// that loosens kid protection asks a grown-up first.
    static var couchSwitcher: NavigationRoute {
        NavigationRoute(
            id: "couchSwitcher",
            style: .sheet
        ) {
            // New members and the grown-up check ask for PINs
            WithLocalUserAuthentication {
                CouchSwitcherView()
            }
        }
    }
}
