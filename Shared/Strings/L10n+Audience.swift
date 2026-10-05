//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// English strings for the "Who's it for?" audience picker (#10).
/// Kept out of the generated `Strings.swift` to avoid merge conflicts.
extension L10n {

    enum Audience {

        static let whosItFor = "Who's it for?"
        static let justMe = "Just me"
        static let theCouch = "The couch"
        static let everyone = "Everyone"
        static let quickPicks = "Quick picks"
        static let recentlyUsed = "Recently used"
        static let people = "People"
        static let save = "Save"
        static let update = "Update"
        static let removeFromWatchlist = "Remove from watchlist"
        static let pickSomeone = "Pick at least one person"
        static let forEveryone = "For everyone"
        static let kid = "Kid"
        static let noPeople = "No signed-in users on this server"
        /// Points at Settings in general: the couch row / switcher there is renamed by #52, and today
        /// "Change who's watching" is the way in. There is no row called "Change who's on the couch".
        static let missingSomeone = "Missing someone? Add them to the couch in Settings."

        /// The poster menu title for a tagged title: "For Sam & Lisa…" (opens the picker).
        static func editAudience(_ sentence: String) -> String {
            "\(sentence)\u{2026}"
        }

        static func forNames(_ names: String) -> String {
            "For \(names)"
        }

        static func others(_ count: Int) -> String {
            count == 1 ? "1 other" : "\(count) others"
        }

        /// Joins names as "Sam", "Sam & Lisa" or "Sam, Lisa & Tuur".
        static func joinedNames(_ names: [String]) -> String {
            guard let last = names.last else { return "" }
            guard names.count > 1 else { return last }

            return names.dropLast().joined(separator: ", ") + " & " + last
        }
    }
}
