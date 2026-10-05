//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

// Seerr screens are iOS only (views live in `Swiftfin/Views/Seerr`).
// #13, #14 and #15 append their routes to this file.

#if os(iOS)
extension NavigationRoute {

    // MARK: - Settings

    static var seerrSettings: NavigationRoute {
        NavigationRoute(
            id: "seerrSettings"
        ) {
            SeerrSettingsView()
        }
    }

    // MARK: - Media Detail

    @MainActor
    static func seerrMedia(mediaType: SeerrMediaType, tmdbID: Int) -> NavigationRoute {
        NavigationRoute(id: "seerr-media-\(mediaType.rawValue)-\(tmdbID)") {
            SeerrMediaDetailView(mediaType: mediaType, tmdbID: tmdbID)
        }
    }

    // MARK: - Watchlists

    static var seerrWatchlists: NavigationRoute {
        NavigationRoute(
            id: "seerr-watchlists"
        ) {
            WatchlistsView()
        }
    }
}
#endif
