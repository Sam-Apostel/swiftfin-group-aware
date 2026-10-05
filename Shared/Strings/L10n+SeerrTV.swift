//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

// English-only strings for Seerr on Apple TV: Discover setup, search and settings (#31).
// Kept out of the generated `Localizable.strings` to avoid merge conflicts.
extension L10n {

    enum SeerrTV {

        // MARK: - Setup: No Server

        static let noServerDescription =
            "Connect Seerr on your iPhone (Settings → Seerr) and it shows up here. Or enter its address on this Apple TV."
        static let enterAddress = "Enter address"
        static let checkAgain = "Check again"

        /// "Tried 192.168.1.10": the household server that adoption tried.
        static func triedHost(_ host: String) -> String {
            "Tried \(host)"
        }

        // MARK: - Setup: Sign In

        static let signIn = "Sign in"
        static let seerrSettings = "Seerr settings"
        static let signInFootnote = "Uses Jellyfin Quick Connect, nothing to type."

        /// "Sign in to Seerr as Sam & Lisa"
        static func signInAs(_ names: String) -> String {
            "Sign in to Seerr as \(names)"
        }

        /// "Signing in Lisa…"
        static func signingIn(_ name: String) -> String {
            "Signing in \(name)…"
        }

        /// "Sam", "Sam & Lisa", "Sam, Lisa & Tuur"
        static func names(_ names: [String]) -> String {
            guard let last = names.last else { return "" }
            guard names.count > 1 else { return last }

            return names.dropLast().joined(separator: ", ") + " & " + last
        }

        // MARK: - Discover

        static let movie = "Movie"
        static let show = "Show"

        /// "★ 7.8"
        static func rating(_ value: Double) -> String {
            "★ " + String(format: "%.1f", value)
        }

        // MARK: - Search

        static let searchHint = "Search movies & shows on Seerr"

        // MARK: - Settings

        static let currentServer = "Current server"
        static let connectAddress = "Connect"
        static let apiKeyFooter = "The API key stays on your iPhone. Apple TV signs each person in with Jellyfin Quick Connect."
        static let signedIn = "Signed in"
        static let signInEveryone = "Sign in everyone"
        static let signOut = "Sign out"

        /// "Use 192.168.1.10 from your household"
        static func useHouseholdServer(_ host: String) -> String {
            "Use \(host) from your household"
        }

        /// "Sign Lisa out of Seerr?"
        static func signOutTitle(_ name: String) -> String {
            "Sign \(name) out of Seerr?"
        }
    }
}
