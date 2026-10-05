//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

// MARK: - SeerrUser

struct SeerrUser: Codable, Hashable, Identifiable, Sendable {

    /// The Seerr user id, used for `X-Api-User`.
    let id: Int
    let displayName: String?
    /// The Jellyfin user id, as stored by Seerr (usually 32 lowercase hex characters).
    let jellyfinUserId: String?
    /// Seerr permission bitmask. `ADMIN` (2) implies every permission.
    let permissions: Int?
    /// Avatar path, relative to the Seerr base URL.
    let avatar: String?

    /// Whether this user's `jellyfinUserId` refers to the given Jellyfin user id,
    /// ignoring case and dashes.
    func matches(jellyfinUserID: String) -> Bool {
        guard let jellyfinUserId else { return false }

        return SeerrUser.normalizedJellyfinUserID(jellyfinUserId) == SeerrUser.normalizedJellyfinUserID(jellyfinUserID)
    }

    /// Lowercased, without dashes: the form Seerr normalizes Jellyfin GUIDs to.
    static func normalizedJellyfinUserID(_ id: String) -> String {
        id.replacing("-", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

extension SeerrUser {

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try container.decode(Int.self, forKey: .id)
        self.displayName = container.decodeNonBlankString(forKey: .displayName)
        self.jellyfinUserId = container.decodeNonBlankString(forKey: .jellyfinUserId)
        self.permissions = container.decodeLeniently(Int.self, forKey: .permissions)
        self.avatar = container.decodeNonBlankString(forKey: .avatar)
    }
}

// MARK: - SeerrRequest

/// A Seerr media request (`MediaRequest`).
struct SeerrRequest: Codable, Hashable, Identifiable, Sendable {

    let id: Int
    let status: SeerrRequestStatus
    let type: SeerrMediaType?
    let media: SeerrMediaInfo?
    let requestedBy: SeerrUser?
    let createdAt: Date?
}

extension SeerrRequest {

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try container.decode(Int.self, forKey: .id)
        self.status = container.decodeLeniently(SeerrRequestStatus.self, forKey: .status) ?? .pending
        self.type = container.decodeLeniently(SeerrMediaType.self, forKey: .type)
        self.media = container.decodeLeniently(SeerrMediaInfo.self, forKey: .media)
        self.requestedBy = container.decodeLeniently(SeerrUser.self, forKey: .requestedBy)
        self.createdAt = container.decodeLeniently(Date.self, forKey: .createdAt)
    }
}

// MARK: - SeerrWatchlistRow

/// A row of a user's Seerr watchlist.
///
/// Local (Jellyfin) users get full rows; Plex users only a subset, so everything is optional.
struct SeerrWatchlistRow: Codable, Hashable, Sendable {

    let id: Int?
    let tmdbId: Int?
    let mediaType: SeerrMediaType?
    let title: String?
}

extension SeerrWatchlistRow {

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.id = container.decodeLeniently(Int.self, forKey: .id)
        self.tmdbId = container.decodeLeniently(Int.self, forKey: .tmdbId)
        self.mediaType = container.decodeLeniently(SeerrMediaType.self, forKey: .mediaType)
        self.title = container.decodeNonBlankString(forKey: .title)
    }
}

// MARK: - SeerrStatus

/// `GET /api/v1/status` (public).
struct SeerrStatus: Codable, Hashable, Sendable {

    /// e.g. `3.5.0`
    let version: String
    let commitTag: String?
}
