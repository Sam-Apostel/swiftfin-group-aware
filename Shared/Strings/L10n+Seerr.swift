//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

extension L10n {

    /// English strings for the Seerr (Jellyseerr / Overseerr) integration.
    enum Seerr {

        // MARK: - Media status

        // One word per status everywhere (badges, detail screens): pending is "Waiting for approval",
        // processing is "Requested", blocklisted is "Blocked".

        static let statusNotRequested = "Not requested"
        /// Seerr's pending status: the request waits for an admin.
        static let statusPending = "Waiting for approval"
        /// Seerr's processing status: approved and on its way.
        static let statusProcessing = "Requested"
        static let statusPartiallyAvailable = "Partially available"
        static let statusAvailable = "Available"
        static let statusBlocklisted = "Blocked"
        static let statusDeleted = "Deleted"

        // MARK: - Request status

        static let requestPendingApproval = "Waiting for approval"
        static let requestApproved = "Approved"
        static let requestDeclined = "Declined"
        static let requestFailed = "Failed"
        static let requestCompleted = "Completed"

        // MARK: - Errors

        /// The button next to Retry on Discover's error screen.
        static let seerrSettings = "Seerr settings"

        static let errorNotConfigured = "Seerr isn't set up for this server."
        static let errorNotConfiguredSuggestion = "Connect your Seerr server in Settings."
        static let errorUnauthorized = "Seerr rejected the API key."
        static let errorUnauthorizedSuggestion = "Check the API key in Seerr under Settings → General."
        static let errorSessionExpired = "Your Seerr sign-in ran out"
        static let errorSessionExpiredSuggestion = "Sign in again in Seerr settings"
        static let errorUnreachableSuggestion = "Check that the Seerr server is on, then try again. Your library still works."
        static let errorDecoding = "Seerr sent a response Couchfin couldn't read."
        static let errorInvalidURL = "Enter a valid Seerr server URL, like http://192.168.1.10:5055."
        static let errorNoServer = "Sign in to a Jellyfin server before connecting Seerr."

        static func errorServer(_ status: Int) -> String {
            "Seerr returned an error (\(status))."
        }

        /// "Can't reach Seerr at seerr.local:5055"
        static func errorUnreachable(_ host: String) -> String {
            "Can't reach Seerr at \(host)"
        }
    }
}
