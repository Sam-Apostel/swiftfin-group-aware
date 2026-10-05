//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import UIKit

extension L10n {

    /// Strings of `CouchGrownUpCheck`.
    enum GrownUpCheck {

        /// The confirmation dialog title when no grown-up has a PIN on this device.
        static let confirmationTitle = "Are you a grown-up?"
        /// The confirming button of that dialog.
        static let confirm = "I'm a grown-up"

        /// The PIN prompt.
        static func enterPin(_ name: String) -> String {
            "A grown-up needs to confirm this. Enter \(name)'s PIN."
        }

        /// The PIN prompt after a wrong PIN.
        static func wrongPin(_ name: String, triesLeft: Int) -> String {
            triesLeft == 1
                ? "That PIN didn't match. Enter \(name)'s PIN (last try)."
                : "That PIN didn't match. Enter \(name)'s PIN (\(triesLeft) tries left)."
        }

        /// The confirmation dialog message: states that the check is not a real lock.
        static var noPinMessage: String {
            "No grown-up has a PIN on this \(deviceName), so anyone can confirm this."
        }

        /// "iPhone", "iPad" or "Apple TV".
        static var deviceName: String {
            if UIDevice.isTV {
                return "Apple TV"
            }

            if UIDevice.isPad {
                return "iPad"
            }

            return "iPhone"
        }
    }
}
