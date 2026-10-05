//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

// Seerr views have the same type names on both platforms:
// iOS in `Swiftfin/Views/Seerr`, tvOS in `Swiftfin tvOS/Views/Seerr`.

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

    #if os(iOS)

    // MARK: - Watchlists

    static var seerrWatchlists: NavigationRoute {
        NavigationRoute(
            id: "seerr-watchlists"
        ) {
            WatchlistsView()
        }
    }
    #endif

    #if os(tvOS)

    // MARK: - Search

    static var seerrSearch: NavigationRoute {
        NavigationRoute(
            id: "seerr-search"
        ) {
            SeerrSearchView()
        }
    }
    #endif
}
