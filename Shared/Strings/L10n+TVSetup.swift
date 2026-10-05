//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

// English-only strings for setting up an Apple TV from the iPhone with Quick Connect (#51).
// Kept out of the generated `Localizable.strings` to avoid merge conflicts.
extension L10n {

    enum TVSetup {

        // MARK: - Apple TV: Quick Connect

        /// The first Quick Connect step on Apple TV: where to enter the code on the iPhone.
        static let quickConnectStepIPhone =
            "On your iPhone: Couchfin › Settings › your name › Quick Connect, then pick who's signing in."
        /// The second step, for another Jellyfin app or the web.
        static let quickConnectStepOtherApp =
            "Or in another Jellyfin app or the web: open your user menu, then Quick Connect."
        /// Under the Quick Connect button on the Apple TV sign-in screen.
        static let quickConnectHint = "Sign in from your iPhone, nothing to type."

        // MARK: - iPhone: Sign in as

        static let signInAs = "Sign in as"

        /// "The other device signs in as Lisa."
        static func signInAsFooter(_ name: String) -> String {
            "The other device signs in as \(name)."
        }
    }
}
