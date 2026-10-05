//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// English strings for the Seerr media detail screen (#14).
/// Kept out of the generated `Strings.swift` to avoid merge conflicts.
extension L10n {

    enum SeerrDetail {

        // MARK: - Status

        static let available = "Available"
        static let blocklisted = "Blocked"
        static let declined = "Declined"
        static let notRequested = "Not requested"
        static let partiallyAvailable = "Partially available"
        /// Seerr's processing status (approved, on its way), and the requested button.
        static let requested = "Requested"
        /// Seerr's pending status: the request waits for an admin.
        static let waitingForApproval = "Waiting for approval"

        // MARK: - Actions

        static let allSeasons = "All seasons"
        static let request = "Request"
        static let requestMoreSeasons = "Request more seasons"
        static let requestSeasons = "Request seasons"
        static let unavailable = "Unavailable"
        static let whosItFor = "Who's it for?"

        // MARK: - Kids

        /// Shown instead of Request when nobody on the couch may request (only kids).
        static let askAGrownUp = "Ask a grown-up"
        /// "Ask a grown-up" once it was pressed: the kids are in the title's audience.
        static let asked = "Asked ✓"
        /// The confirmation line under "Asked ✓". Never claims a notification.
        static let askedConfirmation = "Saved for a grown-up to see on the watchlist"

        /// "Not while Tuur is on the couch": the title is above kid level and a child is on the couch.
        static func notWhileOnTheCouch(_ names: String, count: Int) -> String {
            count == 1 ? "Not while \(names) is on the couch" : "Not while \(names) are on the couch"
        }

        // MARK: - Request offer

        static let requestItToo = "Request it too?"
        static let requestItTooMessage = "It isn't in the library yet. Request it so it's ready for movie night."

        // MARK: - Sections

        static let cast = "Cast"

        // MARK: - Feedback

        static let removedFromWatchlist = "Removed from the watchlist"
        static let requestSent = "Requested"
        static let savedToWatchlist = "Saved to the watchlist"

        // MARK: - Not configured

        static let notConfiguredTitle = "Seerr isn't connected"
        static let notConfiguredDescription = "Connect a Seerr server in Settings to request movies and shows."

        // MARK: - Seasons

        static let seasonsFooter = "Seasons that are already available or requested are skipped."

        static func episodeCount(_ count: Int) -> String {
            count == 1 ? "1 episode" : "\(count) episodes"
        }

        static func requestedBy(_ name: String) -> String {
            "Requested by \(name)"
        }

        static func requestSeasonCount(_ count: Int) -> String {
            count == 1 ? "Request 1 season" : "Request \(count) seasons"
        }

        static func seasonCount(_ count: Int) -> String {
            count == 1 ? "1 season" : "\(count) seasons"
        }

        static func seasonNumber(_ number: Int) -> String {
            "Season \(number)"
        }
    }
}
