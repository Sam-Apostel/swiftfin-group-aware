//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension NavigationRoute {

    /// "What should we watch?": the full-screen decider for a couch.
    ///
    /// Full screen on both platforms. On tvOS the Menu button closes it.
    @MainActor
    static func couchDecider(couch: CouchGroup) -> NavigationRoute {
        NavigationRoute(
            id: "couchDecider",
            style: .fullscreen
        ) {
            CouchDeciderView(couch: couch)
        }
    }
}
