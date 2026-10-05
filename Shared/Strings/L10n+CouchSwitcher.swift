//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

// Strings for changing who's on the couch while signed in (`CouchSwitcherView`),
// the "Still Sam, Lisa & Tuur?" check (`CouchStillHereModifier`) and their entry points.

extension L10n {

    enum CouchSwitcher {

        // MARK: Switcher

        static let title = "Who's on the couch?"
        static let subtitle = "Tap people to add them or take them off. Nobody is signed out."
        static let subtitleTV = "Select people to add them or take them off. Nobody is signed out."

        static let updateCouch = "Update couch"
        static let stopPlaybackFirst = "Stop playback first"

        /// After the switcher closed and signing in the new couch failed.
        static let couldNotUpdate = "Couldn't change who's on the couch"

        /// "Delete" on someone who is on the couch right now.
        static func deleteMemberFirst(_ name: String) -> String {
            "\(name) is on the couch. Take them off the couch and update it before deleting them from this device."
        }

        // MARK: Entry points

        static let changeWhosOnTheCouch = "Change who's on the couch"

        /// The full sign-out button in Settings.
        static let switchUserOrServer = "Switch user or server…"
        static let switchUserOrServerHint = "Signs out the couch so you can pick who's watching"

        /// The VoiceOver label of the avatar stack in the iPhone navigation bar.
        ///
        /// - Parameter names: A localized list of names, e.g. `CouchGroup.displayNames`.
        static func settingsAccessibilityLabel(_ names: String) -> String {
            "Settings. On the couch: \(names)"
        }

        // MARK: Still here?

        /// "Still Sam, Lisa & Tuur?"
        ///
        /// - Parameter names: The names in pick order.
        static func stillHereTitle(_ names: [String]) -> String {
            "Still \(joinedNames(names))?"
        }

        static let stillHereMessage = "Pick Change… when someone left or joined the couch."
        static let change = "Change…"

        /// "Sam", "Sam & Lisa", "Sam, Lisa & Tuur".
        static func joinedNames(_ names: [String]) -> String {
            guard let last = names.last else { return "" }
            guard names.count > 1 else { return last }

            return names.dropLast().joined(separator: ", ") + " & " + last
        }
    }
}
