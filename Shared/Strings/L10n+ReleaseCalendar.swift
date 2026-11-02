//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// English strings for "Coming up", the release calendar.
extension L10n {

    enum ReleaseCalendar {

        // MARK: - Screen

        static let title = "Coming up"
        static let today = "Today"
        static let tomorrow = "Tomorrow"
        static let emptyTitle = "Nothing coming up"
        static let emptyDescription =
            "New episodes of your shows, and the movies and shows you've requested or put on a watchlist, show up here."
        static let seerrUnreachable = "Couldn't reach Seerr"

        // MARK: - Discover card

        static let cardEmpty = "What drops in the next 60 days"

        static func cardNext(title: String, day: String) -> String {
            "Next: \(title), \(day)"
        }

        // MARK: - Entries

        static let newEpisode = "New episode"
        static let seriesPremiere = "Series premiere"
        static let digital = "Digital"
        static let onDisc = "On disc"
        static let inCinemas = "In cinemas"

        static func episodeNumber(season: Int, episode: Int) -> String {
            "S\(season)·E\(episode)"
        }

        static func episodeOnly(_ episode: Int) -> String {
            "E\(episode)"
        }

        static func seasonDrop(season: Int, episodes: Int) -> String {
            "Season \(season) · all \(episodes) episodes"
        }

        // MARK: - Status

        static let statusInLibrarySoon = "Coming to your library"
        static let statusInLibrary = "Already in your library"
        static let statusOnWatchlist = "On a watchlist"

        static func statusRequested(by name: String?) -> String {
            guard let name else { return "Requested" }

            return "Requested by \(name)"
        }

        // MARK: - iPhone calendar

        static let addToCalendar = "Add to my iPhone calendar"
        static let addToCalendarFooter = "Keeps a Couchfin calendar on this iPhone with everything coming up. Turn it off to remove it."
        static let calendarAccessDenied =
            "Couchfin needs full access to your calendars. You can allow it in Settings › Apps › Couchfin › Calendars."
        static let calendarUnavailable = "Couldn't create the Couchfin calendar on this iPhone."

        /// "The Bear · S4·E1"
        static func eventTitle(title: String, subtitle: String) -> String {
            "\(title) · \(subtitle)"
        }

        /// "Dune: Part Three (digital)"
        static func movieEventTitle(title: String, release: String) -> String {
            "\(title) (\(release))"
        }
    }
}
