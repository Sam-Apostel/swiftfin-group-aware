//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

// Note: other couch features add their strings in their own
//       `L10n+Couch<Feature>.swift` file, either as a new enum
//       or as an `extension L10n.Couch { ... }`.
//       Do not declare another `enum Couch` in `L10n`.

extension L10n {

    enum Couch {

        /// Feature name
        static let title = "Couch"

        static let watchingTogether = "Watching together"
        static let whosOnTheCouch = "Who's on the couch?"

        static let kidSafeBrowsing = "Kid-safe browsing"
        static let kidSafeBrowsingDescription =
            "With a kid on the couch, browse as the most restricted member so parental controls apply."

        static let hideWatchedByAnyMember = "Hide what anyone has watched"

        /// - Parameter names: A localized list of names, e.g. `CouchGroup.displayNames`.
        static func watchingAs(_ names: String) -> String {
            "Watching as \(names)"
        }

        /// - Parameter names: A localized list of names, e.g. `CouchGroup.displayNames`.
        static func pickedFor(_ names: String) -> String {
            "Picked for \(names)"
        }
    }
}
