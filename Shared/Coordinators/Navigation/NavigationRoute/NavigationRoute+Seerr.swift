//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

// Seerr screens live in `Shared/Views/Seerr`, for both iOS and tvOS.
// #13, #14 and #15 append their routes to this file.

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

    // MARK: - Search

    #if os(tvOS)
    /// iOS searches Seerr from Discover's navigation bar instead.
    static var seerrSearch: NavigationRoute {
        NavigationRoute(
            id: "seerr-search"
        ) {
            SeerrSearchView()
        }
    }
    #endif

    // MARK: - Watchlists

    static var seerrWatchlists: NavigationRoute {
        NavigationRoute(
            id: "seerr-watchlists"
        ) {
            WatchlistsView()
        }
    }
}
