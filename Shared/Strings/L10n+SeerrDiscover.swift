//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// English strings for the Seerr Discover tab (#13).
extension L10n {

    enum SeerrDiscover {

        // MARK: - Tab

        static let title = "Discover"
        static let searchPrompt = "Movies & shows"

        // MARK: - Not configured

        static let notConfiguredTitle = "Discover with Seerr"
        static let notConfiguredDescription = "Connect Seerr to discover and request movies & shows."

        // MARK: - Rows

        static let familyMovieNight = "Family movie night"
        static let trending = "Trending"
        static let popularMovies = "Popular movies"
        static let popularShows = "Popular shows"
        static let upcomingMovies = "Upcoming movies"
        static let upcomingShows = "Upcoming shows"

        // MARK: - Watchlists card

        static let ourWatchlists = "Our watchlists"
        static let watchlistsEmpty = "Tag movies & shows for whoever's on the couch"

        static func watchlistsSummary(couchCount: Int, totalCount: Int) -> String {
            let picks = couchCount == 1 ? "1 pick for this couch" : "\(couchCount) picks for this couch"
            return "\(picks) · \(totalCount) in total"
        }

        // MARK: - Status

        static let available = "Available"
        static let partiallyAvailable = "Partially available"
        static let processing = "Processing"
        static let requested = "Requested"
        static let onCouchWatchlist = "On a couch watchlist"

        // MARK: - Search

        static let searchFailed = "Search failed"
    }
}
