//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

// MARK: - SeerrMediaDetails

/// Movie or TV details, normalized from `GET /movie/{id}` and `GET /tv/{id}`.
///
/// - Note: `Codable` round-trips this normalized shape. Raw Seerr responses
///         are decoded through `SeerrMovieDetailsResponse` / `SeerrTVDetailsResponse`.
struct SeerrMediaDetails: Codable, Hashable, Identifiable, Sendable {

    /// The TMDB id.
    let id: Int
    let mediaType: SeerrMediaType
    let title: String
    let overview: String?
    let tagline: String?
    let posterPath: String?
    let backdropPath: String?
    /// `releaseDate` for movies, `firstAirDate` for TV (`YYYY-MM-DD`).
    let releaseDate: String?
    /// Movie runtime, or the first episode runtime for TV.
    let runtimeMinutes: Int?
    let voteAverage: Double?
    let genres: [SeerrGenre]
    /// US certification (movie `releases`, TV `contentRatings`), e.g. `PG` or `TV-Y7`.
    let certification: String?
    let numberOfSeasons: Int?
    let seasons: [SeerrSeason]?
    let cast: [SeerrCastMember]
    /// Includes `requests` and `seasons` on details responses.
    let mediaInfo: SeerrMediaInfo?
    /// Whether the current (or `X-Api-User`) user has this title on their Seerr watchlist.
    let onUserWatchlist: Bool?

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

    var stableID: String {
        "\(mediaType.rawValue)-\(id)"
    }

    /// Requestable seasons (specials and empty seasons excluded), matching Seerr's `"all"`.
    var requestableSeasonNumbers: [Int] {
        (seasons ?? [])
            .filter { $0.seasonNumber > 0 && ($0.episodeCount ?? 1) > 0 }
            .map(\.seasonNumber)
    }

    /// A list-style representation, e.g. to reuse poster views.
    var media: SeerrMedia {
        SeerrMedia(
            id: id,
            mediaType: mediaType,
            title: title,
            originalTitle: nil,
            overview: overview,
            posterPath: posterPath,
            backdropPath: backdropPath,
            releaseDate: releaseDate,
            voteAverage: voteAverage,
            genreIds: genres.map(\.id),
            mediaInfo: mediaInfo
        )
    }

    func posterURL(size: String = "w500") -> URL? {
        SeerrImage.url(posterPath, size: size)
    }

    func backdropURL(size: String = "w1280") -> URL? {
        SeerrImage.url(backdropPath, size: size)
    }
}

// MARK: - Supporting types

struct SeerrGenre: Codable, Hashable, Identifiable, Sendable {

    let id: Int
    let name: String
}

struct SeerrSeason: Codable, Hashable, Sendable {

    let seasonNumber: Int
    let name: String?
    let episodeCount: Int?
    let posterPath: String?
}

struct SeerrCastMember: Codable, Hashable, Identifiable, Sendable {

    /// The TMDB person id.
    let id: Int
    let name: String
    let character: String?
    let profilePath: String?

    func profileURL(size: String = "w185") -> URL? {
        SeerrImage.url(profilePath, size: size)
    }
}

// MARK: - Raw responses

/// TMDB-style `{ results: [{ iso_3166_1, ... }] }` wrapper.
struct SeerrCountryResults<Element: Decodable>: Decodable {

    let results: [Element]

    private enum CodingKeys: String, CodingKey {
        case results
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.results = container.decodeLossyArray(Element.self, forKey: .results) ?? []
    }
}

/// `credits` of a details response; only `cast` is used.
struct SeerrCredits: Decodable {

    let cast: [SeerrCastMember]

    private enum CodingKeys: String, CodingKey {
        case cast
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.cast = container.decodeLossyArray(SeerrCastMember.self, forKey: .cast) ?? []
    }
}

/// An entry of a movie's `releases.results` (raw TMDB `release_dates`).
struct SeerrMovieRelease: Decodable {

    struct ReleaseDate: Decodable {

        let certification: String?
        let type: Int?

        private enum CodingKeys: String, CodingKey {
            case certification
            case type
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.certification = container.decodeNonBlankString(forKey: .certification)
            self.type = container.decodeLeniently(Int.self, forKey: .type)
        }
    }

    let countryCode: String?
    let releaseDates: [ReleaseDate]

    private enum CodingKeys: String, CodingKey {
        case countryCode = "iso_3166_1"
        case releaseDates = "release_dates"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.countryCode = container.decodeNonBlankString(forKey: .countryCode)
        self.releaseDates = container.decodeLossyArray(ReleaseDate.self, forKey: .releaseDates) ?? []
    }

    /// The first non-empty certification, preferring theatrical releases (type 3).
    var certification: String? {
        releaseDates.first { $0.type == 3 && $0.certification != nil }?.certification
            ?? releaseDates.first { $0.certification != nil }?.certification
    }
}

/// An entry of a TV show's `contentRatings.results`.
struct SeerrContentRating: Decodable {

    let countryCode: String?
    let rating: String?

    private enum CodingKeys: String, CodingKey {
        case countryCode = "iso_3166_1"
        case rating
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.countryCode = container.decodeNonBlankString(forKey: .countryCode)
        self.rating = container.decodeNonBlankString(forKey: .rating)
    }
}

/// `GET /api/v1/movie/{tmdbId}`.
struct SeerrMovieDetailsResponse: Decodable {

    let id: Int
    let title: String?
    let originalTitle: String?
    let overview: String?
    let tagline: String?
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: String?
    let runtime: Int?
    let voteAverage: Double?
    let genres: [SeerrGenre]
    let credits: SeerrCredits?
    let releases: SeerrCountryResults<SeerrMovieRelease>?
    let mediaInfo: SeerrMediaInfo?
    let onUserWatchlist: Bool?

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case originalTitle
        case overview
        case tagline
        case posterPath
        case backdropPath
        case releaseDate
        case runtime
        case voteAverage
        case genres
        case credits
        case releases
        case mediaInfo
        case onUserWatchlist
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try container.decode(Int.self, forKey: .id)
        self.title = container.decodeNonBlankString(forKey: .title)
        self.originalTitle = container.decodeNonBlankString(forKey: .originalTitle)
        self.overview = container.decodeNonBlankString(forKey: .overview)
        self.tagline = container.decodeNonBlankString(forKey: .tagline)
        self.posterPath = container.decodeNonBlankString(forKey: .posterPath)
        self.backdropPath = container.decodeNonBlankString(forKey: .backdropPath)
        self.releaseDate = container.decodeNonBlankString(forKey: .releaseDate)
        self.runtime = container.decodeLeniently(Int.self, forKey: .runtime)
        self.voteAverage = container.decodeLeniently(Double.self, forKey: .voteAverage)
        self.genres = container.decodeLossyArray(SeerrGenre.self, forKey: .genres) ?? []
        self.credits = container.decodeLeniently(SeerrCredits.self, forKey: .credits)
        self.releases = container.decodeLeniently(SeerrCountryResults<SeerrMovieRelease>.self, forKey: .releases)
        self.mediaInfo = container.decodeLeniently(SeerrMediaInfo.self, forKey: .mediaInfo)
        self.onUserWatchlist = container.decodeLeniently(Bool.self, forKey: .onUserWatchlist)
    }
}

/// `GET /api/v1/tv/{tmdbId}`.
struct SeerrTVDetailsResponse: Decodable {

    let id: Int
    let name: String?
    let originalName: String?
    let overview: String?
    let tagline: String?
    let posterPath: String?
    let backdropPath: String?
    let firstAirDate: String?
    let episodeRunTime: [Int]
    let voteAverage: Double?
    let genres: [SeerrGenre]
    let credits: SeerrCredits?
    let contentRatings: SeerrCountryResults<SeerrContentRating>?
    let numberOfSeasons: Int?
    let seasons: [SeerrSeason]?
    let mediaInfo: SeerrMediaInfo?
    let onUserWatchlist: Bool?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case originalName
        case overview
        case tagline
        case posterPath
        case backdropPath
        case firstAirDate
        case episodeRunTime
        case voteAverage
        case genres
        case credits
        case contentRatings
        case numberOfSeasons
        case seasons
        case mediaInfo
        case onUserWatchlist
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try container.decode(Int.self, forKey: .id)
        self.name = container.decodeNonBlankString(forKey: .name)
        self.originalName = container.decodeNonBlankString(forKey: .originalName)
        self.overview = container.decodeNonBlankString(forKey: .overview)
        self.tagline = container.decodeNonBlankString(forKey: .tagline)
        self.posterPath = container.decodeNonBlankString(forKey: .posterPath)
        self.backdropPath = container.decodeNonBlankString(forKey: .backdropPath)
        self.firstAirDate = container.decodeNonBlankString(forKey: .firstAirDate)
        self.episodeRunTime = container.decodeLossyArray(Int.self, forKey: .episodeRunTime) ?? []
        self.voteAverage = container.decodeLeniently(Double.self, forKey: .voteAverage)
        self.genres = container.decodeLossyArray(SeerrGenre.self, forKey: .genres) ?? []
        self.credits = container.decodeLeniently(SeerrCredits.self, forKey: .credits)
        self.contentRatings = container.decodeLeniently(SeerrCountryResults<SeerrContentRating>.self, forKey: .contentRatings)
        self.numberOfSeasons = container.decodeLeniently(Int.self, forKey: .numberOfSeasons)
        self.seasons = container.decodeLossyArray(SeerrSeason.self, forKey: .seasons)
        self.mediaInfo = container.decodeLeniently(SeerrMediaInfo.self, forKey: .mediaInfo)
        self.onUserWatchlist = container.decodeLeniently(Bool.self, forKey: .onUserWatchlist)
    }
}

// MARK: - Normalization

extension SeerrMediaDetails {

    /// The country used for certifications.
    static let certificationCountry = "US"

    init(movie: SeerrMovieDetailsResponse) {
        let certification = movie.releases?
            .results
            .first { $0.countryCode?.uppercased() == Self.certificationCountry }?
            .certification

        self.init(
            id: movie.id,
            mediaType: .movie,
            title: movie.title ?? movie.originalTitle ?? "",
            overview: movie.overview,
            tagline: movie.tagline,
            posterPath: movie.posterPath,
            backdropPath: movie.backdropPath,
            releaseDate: movie.releaseDate,
            runtimeMinutes: movie.runtime.flatMap { $0 > 0 ? $0 : nil },
            voteAverage: movie.voteAverage,
            genres: movie.genres,
            certification: certification,
            numberOfSeasons: nil,
            seasons: nil,
            cast: movie.credits?.cast ?? [],
            mediaInfo: movie.mediaInfo,
            onUserWatchlist: movie.onUserWatchlist
        )
    }

    init(tv: SeerrTVDetailsResponse) {
        let certification = tv.contentRatings?
            .results
            .first { $0.countryCode?.uppercased() == Self.certificationCountry }?
            .rating

        self.init(
            id: tv.id,
            mediaType: .tv,
            title: tv.name ?? tv.originalName ?? "",
            overview: tv.overview,
            tagline: tv.tagline,
            posterPath: tv.posterPath,
            backdropPath: tv.backdropPath,
            releaseDate: tv.firstAirDate,
            runtimeMinutes: tv.episodeRunTime.first { $0 > 0 },
            voteAverage: tv.voteAverage,
            genres: tv.genres,
            certification: certification,
            numberOfSeasons: tv.numberOfSeasons,
            seasons: tv.seasons,
            cast: tv.credits?.cast ?? [],
            mediaInfo: tv.mediaInfo,
            onUserWatchlist: tv.onUserWatchlist
        )
    }
}
