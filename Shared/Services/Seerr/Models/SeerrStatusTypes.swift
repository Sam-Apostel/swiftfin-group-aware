//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

// MARK: - SeerrMediaType

/// The kind of a Seerr title. Persons and collections are not represented
/// and are dropped while decoding lists.
enum SeerrMediaType: String, Codable, Hashable, CaseIterable, Sendable {
    case movie
    case tv
}

// MARK: - SeerrMediaStatus

/// Availability of a title in Seerr (`server/constants/media.ts`).
///
/// Unknown or missing values decode as `.unknown`.
/// Jellyseerr 2.x's `6 = BLACKLISTED` decodes as `.blocklisted`.
enum SeerrMediaStatus: Int, Codable, Hashable, CaseIterable, Sendable {
    case unknown = 1
    case pending
    case processing
    case partiallyAvailable
    case available
    case blocklisted
    case deleted

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try? container.decode(Int.self)
        self = rawValue.flatMap(Self.init(rawValue:)) ?? .unknown
    }

    /// Whether the title can be played from the Jellyfin library.
    var isAvailable: Bool {
        self == .available || self == .partiallyAvailable
    }

    /// Whether a request for the title is in flight or already fulfilled.
    var isRequested: Bool {
        self == .pending || self == .processing || isAvailable
    }

    var displayTitle: String {
        switch self {
        case .unknown:
            L10n.Seerr.statusNotRequested
        case .pending:
            L10n.Seerr.statusPending
        case .processing:
            L10n.Seerr.statusProcessing
        case .partiallyAvailable:
            L10n.Seerr.statusPartiallyAvailable
        case .available:
            L10n.Seerr.statusAvailable
        case .blocklisted:
            L10n.Seerr.statusBlocklisted
        case .deleted:
            L10n.Seerr.statusDeleted
        }
    }
}

// MARK: - SeerrRequestStatus

/// Status of a Seerr media request (`server/constants/media.ts`).
///
/// Unknown or missing values decode as `.pending`.
enum SeerrRequestStatus: Int, Codable, Hashable, CaseIterable, Sendable {
    case pending = 1
    case approved
    case declined
    case failed
    case completed

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try? container.decode(Int.self)
        self = rawValue.flatMap(Self.init(rawValue:)) ?? .pending
    }

    var displayTitle: String {
        switch self {
        case .pending:
            L10n.Seerr.requestPendingApproval
        case .approved:
            L10n.Seerr.requestApproved
        case .declined:
            L10n.Seerr.requestDeclined
        case .failed:
            L10n.Seerr.requestFailed
        case .completed:
            L10n.Seerr.requestCompleted
        }
    }
}
