//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

// MARK: - Filter

enum WatchlistsFilter: String, CaseIterable, Displayable, Hashable, Identifiable, SystemImageable {

    case all
    case available
    case notAvailable

    var id: String {
        rawValue
    }

    var displayTitle: String {
        switch self {
        case .all:
            L10n.Watchlists.filterAll
        case .available:
            L10n.Watchlists.filterAvailable
        case .notAvailable:
            L10n.Watchlists.filterNotAvailable
        }
    }

    var systemImage: String {
        switch self {
        case .all:
            "line.3.horizontal"
        case .available:
            "checkmark.circle"
        case .notAvailable:
            "clock"
        }
    }

    func includes(_ availability: WatchlistAvailability) -> Bool {
        switch self {
        case .all:
            true
        case .available:
            availability == .inLibrary
        case .notAvailable:
            availability != .inLibrary
        }
    }
}

// MARK: - Availability

enum WatchlistAvailability: Hashable {

    /// Resolved to a Jellyfin library item (or Seerr reports it as available)
    case inLibrary
    /// Seerr has a pending or processing request
    case requested
    /// Seerr knows nothing about it, or it was deleted / blocklisted
    case notRequested
    /// Not in the library, and Seerr is not configured or has not answered (yet)
    case unknown

    var displayTitle: String {
        switch self {
        case .inLibrary:
            L10n.Watchlists.inLibrary
        case .requested:
            L10n.Watchlists.requested
        case .notRequested:
            L10n.Watchlists.notRequested
        case .unknown:
            L10n.Watchlists.notInLibrary
        }
    }

    var systemImage: String {
        switch self {
        case .inLibrary:
            "checkmark.circle.fill"
        case .requested:
            "clock.fill"
        case .notRequested:
            "plus.circle"
        case .unknown:
            "questionmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .inLibrary:
            .green
        case .requested:
            .orange
        case .notRequested, .unknown:
            .secondary
        }
    }
}

// MARK: - Seerr status

/// What Seerr knows about an entry that is not (yet) in the Jellyfin library.
struct WatchlistSeerrStatus: Hashable {

    let status: SeerrMediaStatus
    /// Seerr's link to the Jellyfin item, once it scanned it
    let jellyfinItemID: String?
    let fetchedAt: Date
}

// MARK: - Section

/// Entries that share exactly the same audience.
struct WatchlistsSection: Identifiable {

    /// Sorted member ids joined by "_"
    let id: String
    let audience: Set<String>
    let entries: [AudienceWatchlistEntry]

    static func makeID(audience: Set<String>) -> String {
        audience.sorted().joined(separator: "_")
    }
}
