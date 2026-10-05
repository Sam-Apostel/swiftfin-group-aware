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
        static let blocklisted = "Blocklisted"
        static let notRequested = "Not requested"
        static let partiallyAvailable = "Partially available"
        static let processing = "Processing"
        static let requested = "Requested"

        // MARK: - Actions

        static let allSeasons = "All seasons"
        static let request = "Request"
        static let requestMoreSeasons = "Request more seasons"
        static let requestSeasons = "Request seasons"
        static let unavailable = "Unavailable"
        static let whosItFor = "Who's it for?"

        // MARK: - Request offer

        static let requestItToo = "Request it too?"
        static let requestItTooMessage = "It isn't in the library yet. Request it so it's ready for movie night."

        // MARK: - Sections

        static let cast = "Cast"
        static let moreLikeThis = "More like this"

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
