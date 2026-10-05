//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// One "we want to watch this, and it's for these people" entry of the household watchlist.
///
/// Foundation only: this file is type-checked on Linux.
/// Entries are stored as compact JSON in the Jellyfin DisplayPreferences of every audience member
/// (see `AudienceWatchlistSync`) and merged by `id`, newest `updatedAt` wins.
struct AudienceWatchlistEntry: Codable, Hashable, Identifiable, Sendable {

    enum MediaKind: String, Codable, Hashable, Sendable {
        case movie
        case tv
    }

    /// `"tmdb-movie-862"`, `"tmdb-tv-1399"`, or `"jf-<jellyfinItemId>"` when there is no TMDB id.
    var id: String
    var tmdbID: Int?
    var kind: MediaKind
    var jellyfinItemID: String?
    var title: String
    var year: Int?
    /// TMDB poster path (`"/abc.jpg"`), nil for Jellyfin-only items.
    var posterPath: String?
    /// Jellyfin user ids this entry is meant for.
    var audience: Set<String>
    /// Jellyfin user id of the person who added it.
    var addedBy: String
    var addedAt: Date = .now
    var updatedAt: Date = .now
    /// Tombstone: kept in storage so stale copies don't resurrect it, filtered out of the store's `entries`.
    var isDeleted: Bool = false

    static func makeID(tmdbID: Int?, kind: MediaKind, jellyfinItemID: String?) -> String {
        if let tmdbID {
            return "tmdb-\(kind.rawValue)-\(tmdbID)"
        }
        if let jellyfinItemID, jellyfinItemID.isEmpty == false {
            return "jf-\(jellyfinItemID)"
        }
        return "local-\(UUID().uuidString.lowercased())"
    }
}

// MARK: - Conveniences

extension AudienceWatchlistEntry {

    /// Builds an entry whose `id` is derived with `makeID(tmdbID:kind:jellyfinItemID:)`.
    init(
        tmdbID: Int?,
        kind: MediaKind,
        jellyfinItemID: String?,
        title: String,
        year: Int? = nil,
        posterPath: String? = nil,
        audience: Set<String>,
        addedBy: String,
        addedAt: Date = .now
    ) {
        self.init(
            id: Self.makeID(tmdbID: tmdbID, kind: kind, jellyfinItemID: jellyfinItemID),
            tmdbID: tmdbID,
            kind: kind,
            jellyfinItemID: jellyfinItemID,
            title: title,
            year: year,
            posterPath: posterPath,
            audience: audience,
            addedBy: addedBy,
            addedAt: addedAt,
            updatedAt: addedAt,
            isDeleted: false
        )
    }

    /// TMDB poster URL (w500) for `posterPath`, if any.
    var posterURL: URL? {
        guard let posterPath, posterPath.isEmpty == false else { return nil }

        let path = posterPath.hasPrefix("/") ? posterPath : "/" + posterPath
        return URL(string: "https://image.tmdb.org/t/p/w500\(path)")
    }

    /// True when the audience is exactly `memberIDs`.
    func isForExactAudience(_ memberIDs: Set<String>) -> Bool {
        audience == memberIDs
    }

    /// True when `userID` is part of the audience.
    func includes(_ userID: String) -> Bool {
        audience.contains(userID)
    }
}

// MARK: - Codable

// Custom decoding lives in an extension so the memberwise initializer stays available.
// Decoding is lenient: unknown keys are ignored and optional or defaulted fields may be missing.
extension AudienceWatchlistEntry {

    private enum CodingKeys: String, CodingKey {
        case id
        case tmdbID = "tmdb"
        case kind
        case jellyfinItemID = "jf"
        case title
        case year
        case posterPath = "poster"
        case audience
        case addedBy
        case addedAt
        case updatedAt
        case isDeleted = "deleted"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(String.self, forKey: .id),
            tmdbID: container.decodeIfPresent(Int.self, forKey: .tmdbID),
            kind: container.decodeIfPresent(MediaKind.self, forKey: .kind) ?? .movie,
            jellyfinItemID: container.decodeIfPresent(String.self, forKey: .jellyfinItemID),
            title: container.decodeIfPresent(String.self, forKey: .title) ?? "",
            year: container.decodeIfPresent(Int.self, forKey: .year),
            posterPath: container.decodeIfPresent(String.self, forKey: .posterPath),
            audience: container.decodeIfPresent(Set<String>.self, forKey: .audience) ?? [],
            addedBy: container.decodeIfPresent(String.self, forKey: .addedBy) ?? "",
            addedAt: container.decodeIfPresent(Date.self, forKey: .addedAt) ?? .distantPast,
            updatedAt: container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast,
            isDeleted: container.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(tmdbID, forKey: .tmdbID)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(jellyfinItemID, forKey: .jellyfinItemID)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(year, forKey: .year)
        try container.encodeIfPresent(posterPath, forKey: .posterPath)
        // Sorted, so the stored JSON is stable across writes
        try container.encode(audience.sorted(), forKey: .audience)
        try container.encode(addedBy, forKey: .addedBy)
        try container.encode(addedAt, forKey: .addedAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        if isDeleted {
            try container.encode(true, forKey: .isDeleted)
        }
    }
}
