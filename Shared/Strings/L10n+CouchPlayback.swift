//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

extension L10n {

    /// Strings about mirroring playback to everyone on the couch.
    ///
    /// `names` parameters are localized lists, e.g. "Sam and Lisa".
    enum CouchPlayback {

        /// "Couldn't save progress for Lisa"
        static func couldNotSaveProgress(_ names: String) -> String {
            "Couldn't save progress for \(names)"
        }

        /// "Couldn't save progress for Lisa — their sign-in ran out"
        ///
        /// Every member in `names` needs to sign in again.
        static func couldNotSaveProgressSignInExpired(_ names: String, count: Int) -> String {
            guard count > 1 else {
                return "Couldn't save progress for \(names) — their sign-in ran out"
            }

            return "Couldn't save progress for \(names) — their sign-ins ran out"
        }

        /// "Couldn't save progress for Lisa and Oma — Lisa's sign-in ran out"
        ///
        /// Only the members in `expiredNames` need to sign in again.
        static func couldNotSaveProgress(_ names: String, signInExpiredFor expiredNames: String, count: Int) -> String {
            guard count > 1 else {
                return "Couldn't save progress for \(names) — \(expiredNames)'s sign-in ran out"
            }

            return "Couldn't save progress for \(names) — sign-in ran out for \(expiredNames)"
        }
    }
}
