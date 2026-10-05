//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// Response of `GET /DisplayPreferences/{id}` decoded leniently.
///
/// The SDK's `DisplayPreferencesDto` decodes `CustomPrefs` as `[String: String]`, but a freshly created
/// row returns `"tvhome": null` and `"dashboardTheme": null`, which fails to decode. Only the custom prefs matter here.
struct CouchPrefsDTO: Decodable, Sendable {

    var customPrefs: [String: String?]

    private enum CodingKeys: String, CodingKey {
        case customPrefs = "CustomPrefs"
    }

    init(customPrefs: [String: String?] = [:]) {
        self.customPrefs = customPrefs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.customPrefs = try container.decodeIfPresent([String: String?].self, forKey: .customPrefs) ?? [:]
    }
}

/// Storage format and merge rules of the audience watchlist.
///
/// Foundation only: this file is type-checked and unit-tested on Linux.
enum AudienceWatchlistSync {

    /// DisplayPreferences id used as the store. Must never be an id jellyfin-web uses.
    static let displayPreferencesID = "swiftfin-couch-watchlist"
    /// DisplayPreferences client (≤ 32 characters).
    static let client = "swiftfin-couch"
    /// Every key we own starts with this prefix. Other keys (server defaults) are never written back.
    static let ownedKeyPrefix = "sgw."
    /// One key per entry: `sgw.w.<entry.id>`.
    static let entryKeyPrefix = "sgw.w."
    /// Tombstones older than this are pruned on the next write.
    static let tombstoneLifetime: TimeInterval = 30 * 24 * 60 * 60

    static func key(forEntryID id: String) -> String {
        entryKeyPrefix + id
    }

    // MARK: - Coding

    /// Dates are stored as integer milliseconds since 1970: compact, and stable across decode/encode cycles.
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Int64((date.timeIntervalSince1970 * 1000).rounded()))
        }
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let milliseconds = try container.decode(Double.self)
            return Date(timeIntervalSince1970: milliseconds / 1000)
        }
        return decoder
    }

    static func encode(_ entry: AudienceWatchlistEntry) -> String? {
        guard let data = try? makeEncoder().encode(entry) else { return nil }

        return String(data: data, encoding: .utf8)
    }

    static func decodeEntry(_ value: String) -> AudienceWatchlistEntry? {
        guard let data = value.data(using: .utf8) else { return nil }

        return try? makeDecoder().decode(AudienceWatchlistEntry.self, from: data)
    }

    /// Entries stored in one account's custom prefs, keyed by entry id. Undecodable values are skipped.
    static func entries(in customPrefs: [String: String?]) -> [String: AudienceWatchlistEntry] {
        var result: [String: AudienceWatchlistEntry] = [:]

        for (key, value) in customPrefs {
            guard key.hasPrefix(entryKeyPrefix), let value, let entry = decodeEntry(value) else { continue }

            let id = String(key.dropFirst(entryKeyPrefix.count))
            guard entry.id == id else { continue }

            result[id] = newest(result[id], entry)
        }

        return result
    }

    // MARK: - Merge

    /// The winner of two copies of the same entry: newest `updatedAt`; on a tie the tombstone wins.
    static func newest(_ lhs: AudienceWatchlistEntry?, _ rhs: AudienceWatchlistEntry) -> AudienceWatchlistEntry {
        guard let lhs else { return rhs }

        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt ? lhs : rhs
        }
        if lhs.isDeleted != rhs.isDeleted {
            return lhs.isDeleted ? lhs : rhs
        }
        return lhs
    }

    /// Merges entry maps from several accounts, by id, newest wins.
    static func merge(_ sources: [[String: AudienceWatchlistEntry]]) -> [String: AudienceWatchlistEntry] {
        var result: [String: AudienceWatchlistEntry] = [:]

        for source in sources {
            for (id, entry) in source {
                result[id] = newest(result[id], entry)
            }
        }

        return result
    }

    /// Non-deleted entries, newest first.
    static func visibleEntries(_ all: [String: AudienceWatchlistEntry]) -> [AudienceWatchlistEntry] {
        all.values
            .filter { $0.isDeleted == false }
            .sorted { lhs, rhs in
                if lhs.addedAt != rhs.addedAt {
                    return lhs.addedAt > rhs.addedAt
                }
                return lhs.id < rhs.id
            }
    }

    /// The entry to store when `entry` is upserted and `existing` is the current merged copy.
    ///
    /// Sets `updatedAt` to `now`, clears the tombstone, keeps the original `addedAt`/`addedBy`
    /// of a live entry, and fills ids/poster/year the new copy doesn't know about.
    static func prepareUpsert(
        _ entry: AudienceWatchlistEntry,
        existing: AudienceWatchlistEntry?,
        now: Date
    ) -> AudienceWatchlistEntry {
        var result = entry
        result.isDeleted = false

        if let existing {
            if existing.isDeleted == false {
                result.addedAt = min(existing.addedAt, entry.addedAt)
                if existing.addedBy.isEmpty == false {
                    result.addedBy = existing.addedBy
                }
            }
            result.tmdbID = result.tmdbID ?? existing.tmdbID
            result.jellyfinItemID = result.jellyfinItemID ?? existing.jellyfinItemID
            result.posterPath = result.posterPath ?? existing.posterPath
            result.year = result.year ?? existing.year
            if result.title.isEmpty {
                result.title = existing.title
            }
        }

        // Strictly newer than any stored copy, even with a clock that's slightly behind
        if let existing, existing.updatedAt >= now {
            result.updatedAt = existing.updatedAt.addingTimeInterval(0.001)
        } else {
            result.updatedAt = now
        }

        return result
    }

    /// The tombstone stored when `entry` is removed.
    static func makeTombstone(of entry: AudienceWatchlistEntry, now: Date) -> AudienceWatchlistEntry {
        var tombstone = entry
        tombstone.isDeleted = true
        tombstone.updatedAt = entry.updatedAt >= now ? entry.updatedAt.addingTimeInterval(0.001) : now
        return tombstone
    }

    /// Changes that replace the stale copies in one account's `stored` entries with the `merged` winners.
    ///
    /// This spreads updates and tombstones to every account that holds a copy, so a stale live copy can't
    /// come back once the tombstones elsewhere are pruned.
    static func healingChanges(
        stored: [String: AudienceWatchlistEntry],
        merged: [String: AudienceWatchlistEntry]
    ) -> [String: AudienceWatchlistEntry?] {
        var changes: [String: AudienceWatchlistEntry?] = [:]

        for (id, copy) in stored {
            guard let winner = merged[id], newest(copy, winner) != copy else { continue }

            changes[id] = winner
        }

        return changes
    }

    // MARK: - Writing

    /// The custom prefs to POST for one account.
    ///
    /// - Keeps only our own `sgw.` keys with non-nil values (server-owned keys are reset by the server anyway).
    /// - Applies `changes` (`nil` removes the entry key).
    /// - Prunes tombstones older than `tombstoneLifetime`.
    static func customPrefsForWriting(
        existing: [String: String?],
        changes: [String: AudienceWatchlistEntry?],
        now: Date
    ) -> [String: String] {
        var result: [String: String] = [:]

        for (key, value) in existing {
            guard key.hasPrefix(ownedKeyPrefix), let value else { continue }

            result[key] = value
        }

        for (id, change) in changes {
            let entryKey = key(forEntryID: id)
            if let change, let value = encode(change) {
                result[entryKey] = value
            } else {
                result.removeValue(forKey: entryKey)
            }
        }

        let cutoff = now.addingTimeInterval(-tombstoneLifetime)

        for (key, value) in result where key.hasPrefix(entryKeyPrefix) {
            guard let entry = decodeEntry(value) else { continue }

            if entry.isDeleted, entry.updatedAt < cutoff {
                result.removeValue(forKey: key)
            }
        }

        return result
    }
}
