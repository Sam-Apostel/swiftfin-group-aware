//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// The household's Seerr server, shared through the Jellyfin DisplayPreferences of every household account.
///
/// Only the URL is shared: never the API key, a session cookie or anything else. Each device signs in on its own.
struct SeerrHouseholdConfig: Codable, Hashable, Sendable {

    /// Normalized, without a trailing `/api/v1`.
    var serverURL: String
    var updatedAt: Date
    /// The Jellyfin user id that published it.
    var updatedBy: String
}

/// Storage format of the household Seerr server.
///
/// One DisplayPreferences row per account (`swiftfin-couch-seerr`, client `swiftfin-couch`) with one key:
/// `sgw.seerr.server` → `{"serverURL":"http://192.168.1.10:5055","updatedAt":<ms>,"updatedBy":"<jellyfin user id>"}`.
///
/// Foundation only: this file is type-checked on Linux together with `AudienceWatchlistSync.swift`.
enum SeerrHouseholdConfigSync {

    /// DisplayPreferences id used as the store. Must never be an id jellyfin-web uses.
    static let displayPreferencesID = "swiftfin-couch-seerr"
    static let key = "sgw.seerr.server"

    // MARK: - Coding

    /// Dates in integer milliseconds, like the audience watchlist.
    static func encode(_ config: SeerrHouseholdConfig) -> String? {
        guard let data = try? AudienceWatchlistSync.makeEncoder().encode(config) else { return nil }

        return String(data: data, encoding: .utf8)
    }

    /// `nil` for a missing, undecodable or empty value.
    static func decode(_ value: String?) -> SeerrHouseholdConfig? {
        guard let value, let data = value.data(using: .utf8),
              let config = try? AudienceWatchlistSync.makeDecoder().decode(SeerrHouseholdConfig.self, from: data),
              config.serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        else { return nil }

        return config
    }

    // MARK: - Merge

    /// Newest `updatedAt`; ties → smaller `updatedBy`, so every device picks the same one.
    static func newest(_ configs: [SeerrHouseholdConfig]) -> SeerrHouseholdConfig? {
        configs.min { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            if lhs.updatedBy != rhs.updatedBy {
                return lhs.updatedBy < rhs.updatedBy
            }
            return lhs.serverURL < rhs.serverURL
        }
    }

    // MARK: - Writing

    /// The custom prefs to POST for one account: POST replaces the whole map.
    ///
    /// Keeps every existing non-nil `sgw.` key (server-owned keys are reset by the server anyway) and sets `key`.
    static func customPrefsForWriting(existing: [String: String?], config: SeerrHouseholdConfig) -> [String: String] {
        var result: [String: String] = [:]

        for (existingKey, value) in existing {
            guard existingKey.hasPrefix(AudienceWatchlistSync.ownedKeyPrefix), let value else { continue }

            result[existingKey] = value
        }

        if let value = encode(config) {
            result[key] = value
        }

        return result
    }
}
