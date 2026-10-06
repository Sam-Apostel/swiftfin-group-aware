//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

// MARK: - Couch status on Home

// Reused existing keys: L10n.CouchSettings.onTheCouch(_:), L10n.CouchSettings.browsingAsKidSafe(_:),
// L10n.CouchSwitcher.changeWhosOnTheCouch.

extension L10n {

    enum CouchHomeStatus {

        // MARK: Decider entry, alone on the couch

        static let whatShouldIWatch = "What should I watch?"
        static let letCouchfinPickForYou = "Let Couchfin pick for you"

        // MARK: Status

        /// Shown while `Defaults[.Couch.hideWatchedByAnyMember]` is on, on a group couch.
        static let hidingWatched = "Hiding what anyone watched"

        // MARK: Member health

        /// A member's account couldn't be checked (network, server error); the next refresh may work.
        ///
        /// - Parameter name: The member's name.
        static func couldNotCheck(_ name: String) -> String {
            "Couldn't check \(name) — their history isn't counted"
        }

        /// A member's sign-in ran out, or none is stored.
        ///
        /// - Parameter name: The member's name.
        static func needsSignIn(_ name: String) -> String {
            "\(name) needs to sign in again"
        }

        /// - Parameter name: The member's name.
        static func signInAgainHint(_ name: String) -> String {
            "Opens sign-in for \(name). The couch keeps everyone on it."
        }
    }
}
