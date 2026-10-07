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

        static let statusNotRequested = "Not requested"
        static let statusPending = "Pending"
        static let statusProcessing = "Requested"
        static let statusPartiallyAvailable = "Partially available"
        static let statusAvailable = "Available"
        static let statusBlocklisted = "Blocked"
        static let statusDeleted = "Deleted"

        // MARK: - Request status

        static let requestPendingApproval = "Pending approval"
        static let requestApproved = "Approved"
        static let requestDeclined = "Declined"
        static let requestFailed = "Failed"
        static let requestCompleted = "Completed"

        // MARK: - Errors

        static let errorNotConfigured = "Seerr isn't set up for this server."
        static let errorNotConfiguredSuggestion = "Connect your Seerr server in Settings."
        static let errorUnauthorized = "Seerr rejected the API key."
        static let errorUnauthorizedSuggestion = "Check the API key in Seerr under Settings → General."
        static let errorDecoding = "Seerr sent a response Couchfin couldn't read."
        static let errorInvalidURL = "Enter a valid Seerr server URL, like http://192.168.1.10:5055."
        static let errorNoServer = "Sign in to a Jellyfin server before connecting Seerr."

        static func errorServer(_ status: Int) -> String {
            "Seerr returned an error (\(status))."
        }
    }
}
