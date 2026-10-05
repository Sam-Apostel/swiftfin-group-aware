//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

// MARK: - SeerrMediaInfo

/// The Seerr `Media` row attached to a title.
///
/// - Note: Absent when Seerr has never seen the title (treat as `.unknown`).
///         In list endpoints `requests` is not included and `watchlists`
///         only contains the *current user's* entries.
struct SeerrMediaInfo: Codable, Hashable, Sendable {

    let id: Int?
    let tmdbId: Int?
    let status: SeerrMediaStatus
    /// The Jellyfin item id (32 hex characters, the Series id for TV), once Seerr has scanned it.
    let jellyfinMediaId: String?
    let watchlists: [SeerrWatchlistRow]?
    let requests: [SeerrRequest]?

    /// Whether the current (or `X-Api-User`) user has this title on their Seerr watchlist.
    var isOnWatchlist: Bool {
        watchlists?.isEmpty == false
    }
}

extension SeerrMediaInfo {

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.id = container.decodeLeniently(Int.self, forKey: .id)
        self.tmdbId = container.decodeLeniently(Int.self, forKey: .tmdbId)
        self.status = container.decodeLeniently(SeerrMediaStatus.self, forKey: .status) ?? .unknown
        self.jellyfinMediaId = container.decodeNonBlankString(forKey: .jellyfinMediaId)
        self.watchlists = container.decodeLossyArray(SeerrWatchlistRow.self, forKey: .watchlists)
        self.requests = container.decodeLossyArray(SeerrRequest.self, forKey: .requests)
    }
}

// MARK: - SeerrMedia

/// A movie or TV result from Seerr's discover and search endpoints.
///
/// Persons and collections fail to decode and are dropped by `SeerrPage`.
struct SeerrMedia: Codable, Hashable, Identifiable, Sendable {

    /// The TMDB id.
    let id: Int
    let mediaType: SeerrMediaType
    /// `title` for movies, `name` for TV.
    let title: String
    let originalTitle: String?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    /// `releaseDate` for movies, `firstAirDate` for TV (`YYYY-MM-DD`).
    let releaseDate: String?
    let voteAverage: Double?
    let genreIds: [Int]?
    let mediaInfo: SeerrMediaInfo?

    var year: Int? {
        guard let releaseDate, releaseDate.count >= 4 else { return nil }

        return Int(releaseDate.prefix(4))
    }

    var status: SeerrMediaStatus {
        mediaInfo?.status ?? .unknown
    }

    var jellyfinItemID: String? {
        mediaInfo?.jellyfinMediaId
    }

    /// Unique across movies and TV (TMDB ids are only unique per media type).
    var stableID: String {
        "\(mediaType.rawValue)-\(id)"
    }

    var isOnWatchlist: Bool {
        mediaInfo?.isOnWatchlist ?? false
    }

    func posterURL(size: String = "w342") -> URL? {
        SeerrImage.url(posterPath, size: size)
    }

    func backdropURL(size: String = "w1280") -> URL? {
        SeerrImage.url(backdropPath, size: size)
    }
}

extension SeerrMedia {

    /// Raw keys of Seerr's `MovieResult` / `TvResult`, plus the normalized keys this type encodes.
    private enum RawKeys: String, CodingKey {
        case id
        case mediaType
        case title
        case name
        case originalTitle
        case originalName
        case overview
        case posterPath
        case backdropPath
        case releaseDate
        case firstAirDate
        case voteAverage
        case genreIds
        case mediaInfo
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: RawKeys.self)

        // Required: an unknown `mediaType` (person, collection) throws so the element is dropped
        self.id = try container.decode(Int.self, forKey: .id)
        self.mediaType = try container.decode(SeerrMediaType.self, forKey: .mediaType)

        let originalTitle = container.decodeNonBlankString(forKey: .originalTitle)
            ?? container.decodeNonBlankString(forKey: .originalName)

        self.title = container.decodeNonBlankString(forKey: .title)
            ?? container.decodeNonBlankString(forKey: .name)
            ?? originalTitle
            ?? ""
        self.originalTitle = originalTitle
        self.overview = container.decodeNonBlankString(forKey: .overview)
        self.posterPath = container.decodeNonBlankString(forKey: .posterPath)
        self.backdropPath = container.decodeNonBlankString(forKey: .backdropPath)
        self.releaseDate = container.decodeNonBlankString(forKey: .releaseDate)
            ?? container.decodeNonBlankString(forKey: .firstAirDate)
        self.voteAverage = container.decodeLeniently(Double.self, forKey: .voteAverage)
        self.genreIds = container.decodeLossyArray(Int.self, forKey: .genreIds)
        self.mediaInfo = container.decodeLeniently(SeerrMediaInfo.self, forKey: .mediaInfo)
    }
}

// MARK: - SeerrPage

/// A page of TMDB-style results: `{ page, totalPages, totalResults, results }`.
///
/// Elements that fail to decode (persons, collections, malformed rows) are dropped.
struct SeerrPage<T: Codable & Hashable>: Codable, Hashable {

    let page: Int
    let totalPages: Int
    let totalResults: Int
    let results: [T]

    var hasNextPage: Bool {
        page < totalPages
    }
}

extension SeerrPage {

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let results = container.decodeLossyArray(T.self, forKey: .results) ?? []

        self.page = container.decodeLeniently(Int.self, forKey: .page) ?? 1
        self.totalPages = container.decodeLeniently(Int.self, forKey: .totalPages) ?? 1
        self.totalResults = container.decodeLeniently(Int.self, forKey: .totalResults) ?? results.count
        self.results = results
    }
}

extension SeerrPage: Sendable where T: Sendable {}
