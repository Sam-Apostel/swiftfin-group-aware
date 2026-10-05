//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

// MARK: - Couch home rows

extension L10n {

    enum CouchHome {

        /// Home row: what everyone on the couch is in the middle of.
        static let continueWatchingTogether = "Continue Watching Together"

        /// Home row: the next episode of the shows everyone on the couch is watching.
        static let nextUpTogether = "Next Up Together"

        /// Home row: recently added movies and shows nobody on the couch has watched yet.
        static let newForAllOfYou = "New for All of You"

        /// Home row: watchlist picks tagged for exactly this couch.
        ///
        /// - Parameter names: A localized list of names, e.g. `CouchGroup.displayNames`.
        static func pickedFor(_ names: String) -> String {
            "Picked for \(names)"
        }
    }
}
