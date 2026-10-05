//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

// English-only strings for signing in to Seerr with Jellyfin Quick Connect (#17).
// Kept out of the generated `Localizable.strings` to avoid merge conflicts.
extension L10n {

    enum SeerrQuickConnect {

        // MARK: - Settings

        static let title = "Quick Connect"
        static let signInWithJellyfin = "Sign in with Jellyfin (Quick Connect)"
        static let signInEveryone = "Sign in everyone with Quick Connect"
        static let signIn = "Sign in"
        static let signOut = "Sign out of Seerr"
        static let signedIn = "Signed in"
        static let signedInWithQuickConnect = "Signed in with Quick Connect"
        static let everyoneSignedIn = "Everyone on this device is signed in."
        static let footer =
            "Each person gets their own Seerr session through their Jellyfin account, so no admin API key is needed on this device. Needs Seerr 3.4 or newer and Quick Connect turned on in Jellyfin."
        static let description =
            "Couchfin asks Seerr for a Quick Connect code and approves it with each person's Jellyfin sign-in. Seerr then remembers that person for 30 days; Couchfin signs them in again by itself when the session runs out. Sessions are stored in this device's keychain."

        static func unsupportedVersion(_ version: String) -> String {
            #if os(tvOS)
            // Apple TV can't take an API key: don't suggest one
            return "Seerr \(version) is too old for Apple TV. Update Seerr to 3.4 or newer; your iPhone can keep using its API key meanwhile."
            #else
            return "Seerr \(version) doesn't support Quick Connect. Update to Seerr 3.4 or newer, or use an API key."
            #endif
        }

        // MARK: - Status

        static let apiKeySaved = "API key saved"
        static let removeAPIKey = "Remove API key"
        static let finishSetup = "Sign someone in with Quick Connect or add an API key to start using Seerr."
        static let apiKeyOptionalFooter =
            "Find the API key in Seerr → Settings → General. Leave it empty to sign everyone in with Jellyfin Quick Connect instead."
        static let notSignedIn = "Not signed in"

        // MARK: - Errors

        static let errorNoSession = "Seerr didn't start a session. Check that Seerr is reachable at this address."
        static let errorNoJellyfinAccount = "This person needs to be signed in to Jellyfin on this device first."
        static let errorQuickConnectDisabled =
            "Seerr couldn't start Quick Connect. Make sure Quick Connect is turned on in Jellyfin (Dashboard → General)."
        static let errorAuthorizeFailed = "Jellyfin didn't approve the Quick Connect request."
        static let errorAccessDenied =
            "Seerr refused the sign-in. Import this Jellyfin user in Seerr, or turn on \"Enable New Jellyfin Sign-In\" in Seerr → Settings → Users."
        static let errorNotSignedIn =
            "This person isn't signed in to Seerr. Sign them in with Quick Connect in Settings → Seerr."
        static let errorNoSeerrAccount = "This person doesn't have a Seerr account yet."
    }
}
