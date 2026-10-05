//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

// Strings for starting a couch from the "Who's on the couch?" picker (#45)
// and for `CouchMemberAuthenticator`.

extension L10n {

    enum CouchStart {

        /// The Start button for exactly one person, e.g. "Watch as Lisa".
        static func watchAs(_ name: String) -> String {
            "Watch as \(name)"
        }

        /// The first context-menu item of a person on the picker, e.g. "Watch as just Lisa".
        static func watchAsJust(_ name: String) -> String {
            "Watch as just \(name)"
        }

        /// The PIN prompt after a wrong PIN, e.g. "Wrong PIN for Lisa — try again".
        static func wrongPin(_ name: String) -> String {
            "Wrong PIN for \(name) — try again"
        }

        /// The title of the dialog that offers to start without a person, e.g. "Start without Lisa?".
        static func startWithoutTitle(_ name: String) -> String {
            "Start without \(name)?"
        }

        /// The confirming button of that dialog, e.g. "Start without Lisa".
        static func startWithout(_ name: String) -> String {
            "Start without \(name)"
        }

        /// The dialog message after the last wrong PIN.
        static func wrongPinMessage(_ name: String, tries: Int) -> String {
            "That wasn't \(name)'s PIN \(tries) times. Everyone else stays on the couch."
        }

        /// The dialog message after a person cancelled their PIN or Face ID.
        static func cancelledMessage(_ name: String) -> String {
            "\(name) wasn't confirmed. Everyone else stays on the couch."
        }

        /// The dialog message for a person without a stored sign-in, e.g. "Lisa needs to sign in again on this Apple TV."
        static func needsSignInMessage(_ name: String) -> String {
            "\(name) needs to sign in again on this \(L10n.GrownUpCheck.deviceName). Everyone else stays on the couch."
        }

        /// The error when the only person on the couch has no stored sign-in.
        static func needsSignIn(_ name: String) -> String {
            "\(name) needs to sign in again on this \(L10n.GrownUpCheck.deviceName)."
        }

        /// The kid subtitle when the server puts no age limit on the kid's account.
        static let kidNoAgeLimit = "Kid · no age limit"
        /// The accessibility label of the amber kid badge.
        static let kidNoAgeLimitAccessibilityLabel = "Kid, no age limit on the server"

        /// The accessibility label of the lock glyph next to a person who is asked for a PIN (or Face ID) to start.
        static let locked = "Locked"
    }
}
