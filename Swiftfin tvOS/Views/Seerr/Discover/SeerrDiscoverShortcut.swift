//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

/// The capsule shortcuts below the Discover hero.
enum SeerrDiscoverShortcut: Displayable, SystemImageable {

    case search
    case settings

    var displayTitle: String {
        switch self {
        case .search:
            L10n.search
        case .settings:
            L10n.SeerrTV.seerrSettings
        }
    }

    var systemImage: String {
        switch self {
        case .search:
            "magnifyingglass"
        case .settings:
            "gearshape"
        }
    }
}
