//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

// The JSON the Universes companion app serves (Companion/universes/src/graph.mjs).
// Unknown enum values decode to `.other` so an older Couchfin keeps working with a newer server.

enum UniverseKind: String, Decodable, Hashable, Sendable {

    case fictionalUniverse = "fictional-universe"
    case franchise
    case series
    case character
    case creatorCollab = "creator-collab"
    case nonFiction = "non-fiction"
    case playlist
    case other

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = UniverseKind(rawValue: value) ?? .other
    }

    var displayTitle: String {
        switch self {
        case .fictionalUniverse: L10n.Universes.kindFictionalUniverse
        case .franchise, .other: L10n.Universes.kindFranchise
        case .series: L10n.Universes.kindSeries
        case .character: L10n.Universes.kindCharacter
        case .creatorCollab: L10n.Universes.kindCreators
        case .nonFiction: L10n.Universes.kindNonFiction
        case .playlist: L10n.Universes.kindPlaylist
        }
    }

    var systemImage: String {
        switch self {
        case .fictionalUniverse: "globe.americas.fill"
        case .franchise, .other: "square.stack.3d.up.fill"
        case .series: "list.number"
        case .character: "person.fill"
        case .creatorCollab: "person.3.fill"
        case .nonFiction: "hourglass"
        case .playlist: "text.badge.plus"
        }
    }
}

enum UniverseTimeline: String, Decodable, Hashable, Sendable, Identifiable {

    case release
    case chronological
    case historical
    case lanes

    var id: String {
        rawValue
    }
}

struct UniverseTheme: Decodable, Hashable, Sendable {

    struct Era: Decodable, Hashable, Sendable, Identifiable {
        let label: String
        let start: Int
        let end: Int

        var id: String {
            "\(label)-\(start)"
        }
    }

    let preset: String
    let typeface: String
    let texture: String
    let timelineStyle: String
    let accent: String?
    let eras: [Era]?

    static let fallback = UniverseTheme(
        preset: "cinematic",
        typeface: "sans",
        texture: "grain",
        timelineStyle: "years",
        accent: nil,
        eras: nil
    )
}

struct UniverseCounts: Decodable, Hashable, Sendable {
    let entries: Int
    let inLibrary: Int
    let suggested: Int
}

struct UniverseSpan: Decodable, Hashable, Sendable {
    let from: Int
    let to: Int
}

struct UniverseLink: Decodable, Hashable, Sendable {
    let kind: String
    let url: URL
}

/// A universe in lists: no entries.
struct UniverseSummary: Decodable, Hashable, Identifiable, Sendable {

    let id: String
    let name: String
    let kind: UniverseKind
    let description: String?
    let theme: UniverseTheme
    let timelines: [String]
    let parentIds: [String]
    let childIds: [String]
    let counts: UniverseCounts
    let span: UniverseSpan?
    let sampleItemIds: [String]
    let sampleImageUrls: [URL]
    /// Where the asked-for item sits in the universe (release order), from the item lookup only.
    let position: Int?
}

struct UniverseSeerrRef: Decodable, Hashable, Sendable {
    let mediaType: SeerrMediaType
    let tmdbId: Int
    let status: String?
}

struct UniverseHistorical: Decodable, Hashable, Sendable {
    let start: Int
    let end: Int
    let label: String?
    let source: String?
}

struct UniversePositions: Decodable, Hashable, Sendable {
    /// YYYYMMDD
    let release: Int?
    let chronological: Double?
    let historical: UniverseHistorical?
}

enum UniverseEntryKind: String, Decodable, Hashable, Sendable {

    case movie
    case series
    case book
    case comic
    case game
    case video
    case other

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = UniverseEntryKind(rawValue: value) ?? .other
    }

    var displayTitle: String {
        switch self {
        case .movie: L10n.Universes.kindMovie
        case .series: L10n.Universes.kindShow
        case .book: L10n.Universes.kindBook
        case .comic: L10n.Universes.kindComic
        case .game: L10n.Universes.kindGame
        case .video, .other: L10n.Universes.kindVideo
        }
    }

    var systemImage: String {
        switch self {
        case .movie: "film"
        case .series: "tv"
        case .book: "book.closed"
        case .comic: "text.book.closed"
        case .game: "gamecontroller"
        case .video, .other: "play.rectangle"
        }
    }
}

struct UniverseEntry: Decodable, Hashable, Identifiable, Sendable {

    enum Status: String, Decodable, Hashable, Sendable {
        case confirmed
        case suggested
    }

    let id: String
    let title: String
    let description: String?
    let kind: UniverseEntryKind
    let year: Int?
    let releaseDate: String?
    let jellyfinItemId: String?
    let inLibrary: Bool
    let imageUrl: URL?
    let links: [UniverseLink]
    let seerr: UniverseSeerrRef?
    let positions: UniversePositions
    let lane: String?
    let status: Status
    let reason: String?

    var youtubeURL: URL? {
        links.first { $0.kind == "youtube" }?.url
    }

    var infoURL: URL? {
        links.first { $0.kind == "wikipedia" }?.url
            ?? links.first { $0.kind == "openlibrary" || $0.kind == "anilist" }?.url
            ?? links.first { $0.kind == "wikidata" }?.url
    }
}

struct UniverseRelation: Decodable, Hashable, Sendable {
    let from: String
    let to: String
    let type: String
}

struct Universe: Decodable, Hashable, Identifiable, Sendable {

    let id: String
    let name: String
    let kind: UniverseKind
    let description: String?
    let links: [UniverseLink]
    let sources: [String]
    let parentIds: [String]
    let childIds: [String]
    let theme: UniverseTheme
    let timelines: [String]
    /// What "chronological" means here: "llm" / "curated" (story order), "series", "playlist".
    let orderSource: String?
    let lanes: [String]
    let entries: [UniverseEntry]
    let relations: [UniverseRelation]
    let counts: UniverseCounts

    var availableTimelines: [UniverseTimeline] {
        timelines.compactMap(UniverseTimeline.init(rawValue:))
    }
}

struct UniverseReview: Decodable, Hashable, Identifiable, Sendable {

    struct Entry: Decodable, Hashable, Sendable {
        let id: String
        let title: String
        let kind: UniverseEntryKind
        let year: Int?
        let jellyfinItemId: String?
        let imageUrl: URL?
        let lane: String?
    }

    let id: String
    let universeId: String
    let universeName: String
    let entry: Entry
    let confidence: Double
    let reason: String?
    let question: String
}

struct UniverseServiceStatus: Decodable, Sendable {

    struct Scan: Decodable, Sendable {
        let state: String
        let step: String?
        let error: String?
    }

    struct LastScan: Decodable, Sendable {
        /// ISO 8601 with milliseconds.
        let at: String

        var date: Date? {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.date(from: at) ?? ISO8601DateFormatter().date(from: at)
        }
    }

    struct Counts: Decodable, Sendable {
        let libraryItems: Int
        let universes: Int
        let reviews: Int
    }

    let version: String
    let scan: Scan
    let lastScan: LastScan?
    let counts: Counts
}

// MARK: - Wrappers

struct UniverseList: Decodable, Sendable {
    let universes: [UniverseSummary]
}

struct UniverseReviewList: Decodable, Sendable {
    let reviews: [UniverseReview]
}
