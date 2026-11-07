//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension NavigationRoute {

    static func universe(id: String) -> NavigationRoute {
        NavigationRoute(id: "universe-\(id)") {
            UniverseView(universeID: id)
        }
    }

    static var universes: NavigationRoute {
        NavigationRoute(id: "universes") {
            UniversesListView()
        }
    }

    static var universeReviews: NavigationRoute {
        NavigationRoute(id: "universe-reviews") {
            UniverseReviewsView()
        }
    }

    static var universeSettings: NavigationRoute {
        NavigationRoute(id: "universe-settings") {
            UniverseSettingsView()
        }
    }
}
