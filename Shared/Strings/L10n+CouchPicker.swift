//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

// Strings for the "Who's on the couch?" picker (`SelectUserView`).

extension L10n {

    enum CouchPicker {

        static let title = "Who's on the couch?"
        static let subtitle = "Tap everyone who's watching"

        static let startWatching = "Start watching"

        static func startWatchingTogether(_ count: Int) -> String {
            "Start watching together (\(count))"
        }

        static let kid = "Kid"
        static let markAsKid = "Mark as kid"
        static let unmarkAsKid = "Unmark as kid"

        /// Shown in the avatar stack when more members are on the couch than avatars fit.
        static func moreMembers(_ count: Int) -> String {
            "+\(count)"
        }
    }
}
