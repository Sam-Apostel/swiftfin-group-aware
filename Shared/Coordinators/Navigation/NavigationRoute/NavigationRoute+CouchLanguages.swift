//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension NavigationRoute {

    /// One person's language profile: Jellyfin audio and subtitle preferences plus the couch-only extras.
    @MainActor
    static func couchLanguageProfile(userID: String) -> NavigationRoute {
        NavigationRoute(
            id: "couchLanguageProfile-\(userID)"
        ) {
            CouchLanguageProfileView(userID: userID)
        }
    }

    /// A multi-select list of languages. `selection` holds canonical codes (`CouchLanguageCode.canonical`).
    @MainActor
    static func couchLanguageList(title: String, selection: Binding<[String]>) -> NavigationRoute {
        NavigationRoute(
            id: "couchLanguageList"
        ) {
            CouchLanguageListPicker(title: title, selection: selection)
        }
    }
}
