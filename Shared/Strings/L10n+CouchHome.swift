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

        /// The primary user's own Continue Watching, as a title for `personalRow(name:title:)`.
        static let continueWatching = "Continue Watching"

        /// Home row of one person's own list on a group's home, e.g. "Sam's Continue Watching".
        ///
        /// - Parameters:
        ///   - name: The person's name.
        ///   - title: The row's usual title, e.g. `continueWatching` or `L10n.nextUp`.
        static func personalRow(name: String, title: String) -> String {
            "\(name)'s \(title)"
        }

        /// Home row: watchlist picks tagged for exactly this couch.
        ///
        /// - Parameter names: A localized list of names, e.g. `CouchGroup.displayNames`.
        static func pickedFor(_ names: String) -> String {
            "Picked for \(names)"
        }

        /// Home row on a couch with a kid and grown-ups: family films everyone on the couch can watch.
        static let familyMovieNight = "Family movie night"
    }
}
