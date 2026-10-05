//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

// English-only strings for the Seerr settings screen (#12).
// Kept out of the generated `Localizable.strings` to avoid merge conflicts.
extension L10n {

    enum SeerrSettings {

        // MARK: - Settings Entry

        static let title = "Seerr"
        static let requests = "Requests"
        static let notConnected = "Not connected"
        static let requestsFooter = "Discover, request and keep watchlists for movies and shows through your Seerr or Jellyseerr server."

        // MARK: - Server

        static let urlPrompt = "http://seerr.local:5055"
        static let apiKey = "API key"
        static let apiKeyFooter = "Find the API key in Seerr → Settings → General."
        static let apiKeyDescription = "The API key is in the Seerr web app under Settings → General. It is stored in this device's keychain."
        static let missingAPIKey = "Enter the Seerr API key."
        static let serverURLDescription = "The address of your Seerr or Jellyseerr server, for example http://192.168.1.10:5055. If you leave out http:// or https://, http:// is used."

        // MARK: - Status

        static let connected = "Connected"
        static func connectedTo(_ version: String) -> String {
            "Connected to Seerr \(version)"
        }

        static let update = "Update"
        /// Shown instead of "Connected" when `/status` just failed.
        static let unreachable = "Can't reach Seerr right now"

        // MARK: - Sign In

        /// "Couldn't sign Tuur in: Access denied."
        static func couldNotSignIn(_ name: String, _ message: String) -> String {
            "Couldn't sign \(name) in: \(message)"
        }

        // MARK: - People

        static let notFound = "Not found"
        /// "Tuur (imported)": a Jellyfin user that was just imported into Seerr.
        static func imported(_ seerrName: String) -> String {
            "\(seerrName) (imported)"
        }

        static let peopleFooter = "Everyone signed in on this Jellyfin server is matched to their Seerr account. Missing accounts are imported from Jellyfin."
        static let noPeople = "No one is signed in on this server."

        // MARK: - Learn More

        static let asEachPerson = "Requests as each person"
        static let asEachPersonDescription =
            "Requests and watchlists are made as each person, so Seerr shows who asked for what — with Quick Connect, or the API key if you added one."

        // MARK: - Disconnect

        static let disconnect = "Disconnect"
        static let disconnectTitle = "Disconnect from Seerr?"
        static let disconnectMessage = "Requests and Seerr watchlists won't be available on this device until you connect again."
    }
}
