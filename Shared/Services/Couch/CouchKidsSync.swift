//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// Whether a user is marked as a kid, and when that was last decided.
///
/// Synced household-wide through the `swiftfin-couch-kids` DisplayPreferences row
/// of every account, so a kid marked on one device is a kid on every device.
struct CouchKidFlag: Codable, Hashable, Sendable {

    var isKid: Bool
    var updatedAt: Date
    /// The user id of the account that made the change, when known.
    var updatedBy: String?

    init(isKid: Bool, updatedAt: Date, updatedBy: String? = nil) {
        self.isKid = isKid
        self.updatedAt = updatedAt
        self.updatedBy = updatedBy
    }
}

/// The pure merge rules of the household kid flags. Foundation only.
///
/// The row holds one JSON map `[userID: CouchKidFlag]` under `prefsKey`.
///
/// Kid-safety invariants:
/// - per user, the newest `updatedAt` wins, and on a tie the kid flag wins;
/// - a local kid flag without a timestamp (from before syncing existed) is seeded as new;
/// - a local `false` without a timestamp is never published.
enum CouchKidsSync {

    /// The DisplayPreferences id of the kids row (client `swiftfin-couch`).
    static let displayPreferencesID = "swiftfin-couch-kids"

    /// The custom prefs key holding the JSON map of kid flags.
    static let prefsKey = "sgw.kids.v1"

    // MARK: - Merge

    /// The newer of two flags. On a tie, the kid flag wins.
    static func newest(_ lhs: CouchKidFlag?, _ rhs: CouchKidFlag?) -> CouchKidFlag? {
        guard let lhs else { return rhs }
        guard let rhs else { return lhs }

        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt ? lhs : rhs
        }

        if lhs.isKid != rhs.isKid {
            return lhs.isKid ? lhs : rhs
        }

        return lhs
    }

    /// Merges two maps per user: the newest `updatedAt` wins, on a tie `isKid == true` wins.
    static func merge(
        _ lhs: [String: CouchKidFlag],
        _ rhs: [String: CouchKidFlag]
    ) -> [String: CouchKidFlag] {
        var merged = lhs

        for (userID, flag) in rhs {
            merged[userID] = newest(merged[userID], flag)
        }

        return merged
    }

    /// Merges any number of maps with `merge(_:_:)`.
    static func merge(_ maps: [[String: CouchKidFlag]]) -> [String: CouchKidFlag] {
        maps.reduce(into: [:]) { result, map in
            result = merge(result, map)
        }
    }

    /// Adds a kid flag stamped `now` for every local kid that has no entry yet.
    ///
    /// A local `false` is never seeded: without a timestamp it would override real decisions.
    static func seeded(
        remote: [String: CouchKidFlag],
        localKidIDs: Set<String>,
        now: Date
    ) -> [String: CouchKidFlag] {
        var seeded = remote
        let stamp = roundedToMilliseconds(now)

        for userID in localKidIDs where seeded[userID] == nil {
            seeded[userID] = CouchKidFlag(isKid: true, updatedAt: stamp, updatedBy: nil)
        }

        return seeded
    }

    /// Whether a stored row needs to be written to hold `merged`.
    static func needsWrite(stored: [String: CouchKidFlag], merged: [String: CouchKidFlag]) -> Bool {
        stored != merged
    }

    /// The complete custom prefs to post for a row: the other keys of the row are kept,
    /// the kid flags are replaced with `merged`.
    static func customPrefsForWriting(
        existing: [String: String?],
        merged: [String: CouchKidFlag]
    ) -> [String: String]? {
        guard let encoded = encode(merged) else { return nil }

        var customPrefs: [String: String] = [:]

        for (key, value) in existing {
            if let value {
                customPrefs[key] = value
            }
        }

        customPrefs[prefsKey] = encoded
        return customPrefs
    }

    /// The kid flags stored in a row's custom prefs. Unreadable values count as no flags.
    static func flags(in customPrefs: [String: String?]) -> [String: CouchKidFlag] {
        guard let value = customPrefs[prefsKey] else { return [:] }

        return decode(value)
    }

    // MARK: - Coding

    /// JSON with dates as milliseconds since 1970 and sorted keys.
    static func encode(_ flags: [String: CouchKidFlag]) -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(milliseconds(of: date))
        }
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        guard let data = try? encoder.encode(flags) else { return nil }

        return String(data: data, encoding: .utf8)
    }

    /// Decodes a row value. `nil`, empty or unreadable values decode to no flags.
    static func decode(_ string: String?) -> [String: CouchKidFlag] {
        guard let string, let data = string.data(using: .utf8), data.isEmpty == false else { return [:] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let milliseconds = try container.decode(Double.self)
            return Date(timeIntervalSince1970: milliseconds / 1000)
        }

        return (try? decoder.decode([String: CouchKidFlag].self, from: data)) ?? [:]
    }

    // MARK: - Dates

    /// Milliseconds since 1970, the precision of the synced dates.
    static func milliseconds(of date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    /// The date at the precision the row stores, so local and synced dates compare equal.
    static func roundedToMilliseconds(_ date: Date) -> Date {
        Date(timeIntervalSince1970: Double(milliseconds(of: date)) / 1000)
    }
}
