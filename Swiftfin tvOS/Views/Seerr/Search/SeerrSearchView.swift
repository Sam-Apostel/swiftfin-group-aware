//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

/// tvOS placeholder for the pushed Seerr search screen (`NavigationRoute.seerrSearch`).
///
/// Replaced by the tvOS Discover issue.
struct SeerrSearchView: View {

    init() {}

    var body: some View {
        ContentUnavailableView(L10n.SeerrDiscover.notConfiguredTitle, systemImage: "popcorn")
    }
}
