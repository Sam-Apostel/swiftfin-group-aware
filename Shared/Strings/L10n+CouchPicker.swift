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
        static let subtitleTV = "Select everyone who's watching"
        /// Shown under the title while no users are stored for the shown servers.
        static let emptySubtitle = "Add everyone who watches here — you'll pick who's on the couch each time."

        static let addPerson = "Add person"
        /// Shown for a stored user without a working sign-in, and as a context-menu item for every user.
        static let signInAgain = "Sign in again"
        /// The toggle on the sign-in screen that marks the new user as a kid.
        static let thisIsAKid = "This is a kid"

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
