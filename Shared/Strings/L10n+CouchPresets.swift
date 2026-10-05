//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

// Strings for the couch preset chips on the "Who's on the couch?" picker (#18).

extension L10n {

    enum CouchPresets {

        static let saveThisCouch = "Save this couch…"
        static let saveCouchTitle = "Save this couch"
        static let editCouchTitle = "Edit couch"
        static let editCouch = "Edit this couch…"
        static let forget = "Forget"
        static let namePlaceholder = "Name, e.g. Date night"
        static let emojiPlaceholder = "Emoji (optional)"
        static let savedCouches = "Saved couches"

        /// The alert message, e.g. "Sam & Lisa".
        static func members(_ names: [String]) -> String {
            L10n.Audience.joinedNames(names)
        }

        /// Accessibility hint of a selected chip.
        static let startHint = "Tap again to start watching"
        /// Accessibility hint of a chip that is not selected.
        static let selectHint = "Puts these people on the couch"
    }
}
