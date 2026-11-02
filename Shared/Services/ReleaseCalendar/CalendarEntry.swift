//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// Something that drops on a given day: an episode, a whole season, a movie or a new show.
struct CalendarEntry: Hashable, Identifiable, Sendable {

    enum Kind: String, Hashable, Sendable {
        case episode
        /// Three or more episodes of the same season on the same day.
        case seasonDrop
        case movie
        case seriesPremiere
    }

    enum Status: Hashable, Sendable {
        /// An episode of a show in the library that hasn't arrived yet.
        case inLibrarySoon
        /// Already in the library, ahead of its air date.
        case inLibrary
        /// Requested in Seerr, by this person when known.
        case requested(by: String?)
        /// On one of the household watchlists.
        case onWatchlist
    }

    enum Destination: Hashable, Sendable {
        case jellyfinItem(id: String)
        case seerr(mediaType: SeerrMediaType, tmdbID: Int)
    }

    /// Stable across refreshes: used to match calendar events.
    let id: String
    let kind: Kind
    /// The start of the release day in the current time zone, or the exact air time when `isTimeKnown`.
    let date: Date
    let isTimeKnown: Bool
    /// The show or movie.
    let title: String
    /// e.g. `S2·E5`, `Season 2 · all 8 episodes`, `Digital`, `In cinemas`.
    let subtitle: String
    /// The episode title, when there is one.
    let detail: String?
    let imageURL: URL?
    let destination: Destination
    let status: Status

    var systemImage: String {
        switch kind {
        case .episode:
            "tv"
        case .seasonDrop:
            "square.stack.3d.up.fill"
        case .movie:
            "film"
        case .seriesPremiere:
            "sparkles.tv"
        }
    }

    /// "The Bear · S4·E1", "Dune: Part Three (digital)"
    var eventTitle: String {
        switch kind {
        case .movie:
            L10n.ReleaseCalendar.movieEventTitle(title: title, release: subtitle.lowercased())
        case .episode, .seasonDrop, .seriesPremiere:
            L10n.ReleaseCalendar.eventTitle(title: title, subtitle: subtitle)
        }
    }

    var statusTitle: String {
        switch status {
        case .inLibrarySoon:
            L10n.ReleaseCalendar.statusInLibrarySoon
        case .inLibrary:
            L10n.ReleaseCalendar.statusInLibrary
        case let .requested(name):
            L10n.ReleaseCalendar.statusRequested(by: name)
        case .onWatchlist:
            L10n.ReleaseCalendar.statusOnWatchlist
        }
    }

    var statusSystemImage: String {
        switch status {
        case .inLibrarySoon:
            "clock.fill"
        case .inLibrary:
            "checkmark.circle.fill"
        case .requested:
            "paperplane.fill"
        case .onWatchlist:
            "sofa.fill"
        }
    }
}
