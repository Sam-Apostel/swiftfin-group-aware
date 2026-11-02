//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

// MARK: - SeerrReleaseDetails

/// The release dates of a movie or show, from `GET /movie/{id}` or `GET /tv/{id}`.
///
/// Used by "Coming up". Everything is optional and decoded leniently, so a
/// missing or unexpected field never fails the whole response.
struct SeerrReleaseDetails: Decodable, Hashable, Sendable {

    /// The TMDB id.
    let id: Int
    /// `title` for movies, `name` for TV.
    let title: String?
    let posterPath: String?
    let backdropPath: String?
    /// `releaseDate` for movies (`YYYY-MM-DD`).
    let releaseDate: String?
    /// `firstAirDate` for TV (`YYYY-MM-DD`).
    let firstAirDate: String?
    /// Movie releases per country (raw TMDB `release_dates`).
    let releases: [SeerrReleaseCountry]
    /// TV only.
    let nextEpisodeToAir: SeerrReleaseEpisode?
    let mediaInfo: SeerrMediaInfo?

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case name
        case originalTitle
        case originalName
        case posterPath
        case backdropPath
        case releaseDate
        case firstAirDate
        case releases
        case nextEpisodeToAir
        case mediaInfo
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try container.decode(Int.self, forKey: .id)
        self.title = container.decodeNonBlankString(forKey: .title)
            ?? container.decodeNonBlankString(forKey: .name)
            ?? container.decodeNonBlankString(forKey: .originalTitle)
            ?? container.decodeNonBlankString(forKey: .originalName)
        self.posterPath = container.decodeNonBlankString(forKey: .posterPath)
        self.backdropPath = container.decodeNonBlankString(forKey: .backdropPath)
        self.releaseDate = container.decodeNonBlankString(forKey: .releaseDate)
        self.firstAirDate = container.decodeNonBlankString(forKey: .firstAirDate)
        self.releases = container.decodeLeniently(SeerrReleaseCountryResults.self, forKey: .releases)?.results ?? []
        self.nextEpisodeToAir = container.decodeLeniently(SeerrReleaseEpisode.self, forKey: .nextEpisodeToAir)
        self.mediaInfo = container.decodeLeniently(SeerrMediaInfo.self, forKey: .mediaInfo)
    }
}

// MARK: - Movie releases

/// `releases` of a movie: `{ results: [...] }`.
private struct SeerrReleaseCountryResults: Decodable {

    let results: [SeerrReleaseCountry]

    private enum CodingKeys: String, CodingKey {
        case results
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.results = container.decodeLossyArray(SeerrReleaseCountry.self, forKey: .results) ?? []
    }
}

/// The releases of a movie in one country.
struct SeerrReleaseCountry: Decodable, Hashable, Sendable {

    /// e.g. `US`, `BE`
    let countryCode: String?
    let releaseDates: [SeerrReleaseDate]

    private enum CodingKeys: String, CodingKey {
        case countryCode = "iso_3166_1"
        case releaseDates = "release_dates"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.countryCode = container.decodeNonBlankString(forKey: .countryCode)
        self.releaseDates = container.decodeLossyArray(SeerrReleaseDate.self, forKey: .releaseDates) ?? []
    }
}

/// One release of a movie.
struct SeerrReleaseDate: Decodable, Hashable, Sendable {

    /// TMDB release types.
    enum ReleaseType: Int, Hashable, Sendable {
        case premiere = 1
        case theatricalLimited
        case theatrical
        case digital
        case physical
        case tv
    }

    let type: ReleaseType?
    /// ISO 8601, e.g. `2026-03-14T00:00:00.000Z`. Only the date part is meaningful.
    let releaseDate: String?

    private enum CodingKeys: String, CodingKey {
        case type
        case releaseDate = "release_date"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = container.decodeLeniently(Int.self, forKey: .type).flatMap(ReleaseType.init(rawValue:))
        self.releaseDate = container.decodeNonBlankString(forKey: .releaseDate)
    }
}

// MARK: - TV episodes

/// `nextEpisodeToAir` of a show, or an episode of a season.
struct SeerrReleaseEpisode: Decodable, Hashable, Sendable {

    let name: String?
    /// `YYYY-MM-DD`
    let airDate: String?
    let seasonNumber: Int?
    let episodeNumber: Int?

    private enum CodingKeys: String, CodingKey {
        case name
        case airDate
        case seasonNumber
        case episodeNumber
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = container.decodeNonBlankString(forKey: .name)
        self.airDate = container.decodeNonBlankString(forKey: .airDate)
        self.seasonNumber = container.decodeLeniently(Int.self, forKey: .seasonNumber)
        self.episodeNumber = container.decodeLeniently(Int.self, forKey: .episodeNumber)
    }
}

/// `GET /tv/{id}/season/{seasonNumber}`: only the episodes are used.
struct SeerrReleaseSeason: Decodable, Hashable, Sendable {

    let episodes: [SeerrReleaseEpisode]

    private enum CodingKeys: String, CodingKey {
        case episodes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.episodes = container.decodeLossyArray(SeerrReleaseEpisode.self, forKey: .episodes) ?? []
    }
}
