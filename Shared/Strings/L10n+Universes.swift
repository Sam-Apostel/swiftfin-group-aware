//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// English strings for Universes: shared worlds, timelines and backlogs.
extension L10n {

    enum Universes {

        // MARK: - Titles

        static let title = "Universes"
        static let partOf = "Part of"
        static let suggestions = "Suggestions"

        // MARK: - Discover card

        static let cardEmpty = "Shared worlds, timelines and backlogs"

        static func cardCount(_ count: Int) -> String {
            count == 1 ? "1 universe in your library" : "\(count) universes in your library"
        }

        // MARK: - Kinds

        static let kindFictionalUniverse = "Fictional universe"
        static let kindFranchise = "Franchise"
        static let kindSeries = "Series"
        static let kindCharacter = "Character"
        static let kindCreators = "Creators"
        static let kindNonFiction = "Non-fiction"
        static let kindPlaylist = "Backlog"

        // MARK: - Timelines

        static let timelineRelease = "Release order"
        static let timelineStory = "Story order"
        static let timelineSeries = "Series order"
        static let timelinePlaylist = "Playlist order"
        static let timelineHistory = "History"
        static let timelineLanes = "By creator"
        static let unknownDate = "Date unknown"
        static let undated = "Not dated"

        static func span(from: Int, to: Int) -> String {
            from == to ? Self.year(from) : "\(Self.year(from)) – \(Self.year(to))"
        }

        /// "2019", "500 BCE", "13.8 billion years ago".
        static func year(_ year: Int) -> String {
            if year <= -1_000_000_000 {
                return String(format: "%.1f billion years ago", Double(-year) / 1_000_000_000)
            }
            if year <= -1_000_000 {
                return "\(-year / 1_000_000) million years ago"
            }
            if year <= -10000 {
                return "\(-year / 1000)k BCE"
            }
            return year < 0 ? "\(-year) BCE" : String(year)
        }

        // MARK: - Counts

        static func inLibrary(_ count: Int, of total: Int) -> String {
            "\(count) of \(total) in your library"
        }

        static func watched(_ count: Int, of total: Int) -> String {
            "Watched \(count) of \(total)"
        }

        static func position(_ position: Int, of total: Int) -> String {
            "\(position) of \(total)"
        }

        // MARK: - Entries

        static let notInLibrary = "Not in your library"
        static let suggested = "Suggested"
        static let requested = "Requested"
        static let available = "Available"
        static let request = "Request"
        static let openOnYouTube = "Open on YouTube"
        static let onYouTube = "On YouTube"
        static let moreInfo = "More info"
        static let notPartOfUniverse = "Not part of this universe"
        static let belongsHere = "Yes, it belongs here"
        static let kindMovie = "Movie"
        static let kindShow = "Show"
        static let kindBook = "Book"
        static let kindComic = "Comic"
        static let kindGame = "Game"
        static let kindVideo = "Video"
        static let showOnlyLibrary = "Only what I have"
        static let showEverything = "Everything"

        static func suggestedBecause(_ reason: String) -> String {
            "Suggested: \(reason)"
        }

        // MARK: - Reviews

        static let reviewTitle = "Does this belong?"
        static let reviewEmpty = "Nothing to review"
        static let reviewEmptyDescription = "When the AI isn't sure where a video belongs, it asks here."
        static let yes = "Yes"
        static let no = "No"

        static func reviewCount(_ count: Int) -> String {
            count == 1 ? "1 suggestion to review" : "\(count) suggestions to review"
        }

        // MARK: - Empty / errors

        static let emptyTitle = "No universes yet"
        static let emptyDescription =
            "Install Universes from the Couchfin store on your Umbrel, paste a Jellyfin API key and let it scan."
        static let notConnectedTitle = "Universes isn't connected"
        static let notConnectedDescription =
            "Universes runs next to Jellyfin on your server. Couchfin looks for it automatically; you can also enter its address."
        static let scanning = "Scanning your library…"
        static let errorUnreachable = "Couldn't reach Universes"
        static let errorUnauthorized = "Universes didn't accept this Jellyfin sign-in"

        static func errorServer(_ status: Int) -> String {
            "Universes answered with an error (\(status))"
        }

        static let errorDecoding = "Universes sent something Couchfin doesn't understand. Update the Universes app."

        // MARK: - Settings

        static let settingsTitle = "Universes"
        static let settingsFooter =
            "The Universes app runs next to Jellyfin (on umbrelOS: install it from the Couchfin store). Couchfin signs in with your Jellyfin account."
        static let urlPrompt = "http://umbrel.local:7457"
        static let findAutomatically = "Find automatically"
        static let connect = "Connect"
        static let disconnect = "Disconnect"
        static let notConnected = "Not connected"
        static let lastScan = "Last scan"
        static let scanNow = "Scan now"
        static let scanStarted = "Scan started"
        static let universesCount = "Universes"
        static let reviewsCount = "To review"
        static let notFound = "Couldn't find Universes next to this Jellyfin server. Enter its address."
        static let theme = "Themed timelines"
        static let themeFooter = "Colours, type and texture follow each universe. Turn off for Couchfin's own look."
    }
}
