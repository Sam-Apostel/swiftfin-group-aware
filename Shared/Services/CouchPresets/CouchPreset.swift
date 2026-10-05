//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// A named couch ("Date night", "With Tuur") that can be picked with one tap.
///
/// Presets are shared by the household: they are stored in the Jellyfin DisplayPreferences of every
/// account on the server (see `CouchPresetSync`), so they sync between the iPhone and the Apple TV.
///
/// Foundation only: this file is type-checked and unit-tested on Linux.
struct CouchPreset: Codable, Hashable, Identifiable, Sendable {

    var id: String
    var name: String
    /// The members in pick order. The first member is the preferred primary user.
    var memberIDs: [String]
    /// A single emoji (or character) shown on the chip. `nil` shows a couch icon.
    var emoji: String?
    var updatedAt: Date
    /// Tombstone: a deleted preset is kept, so a stale copy elsewhere can't bring it back.
    var isDeleted: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case memberIDs
        case emoji
        case updatedAt
        case isDeleted
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        memberIDs: [String],
        emoji: String? = nil,
        updatedAt: Date = .now,
        isDeleted: Bool = false
    ) {
        self.id = id
        self.name = name
        self.memberIDs = memberIDs
        self.emoji = emoji
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
    }

    /// Lenient: copies written by a later version with extra or missing fields still decode.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.memberIDs = try container.decodeIfPresent([String].self, forKey: .memberIDs) ?? []
        self.emoji = try container.decodeIfPresent(String.self, forKey: .emoji)
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
        self.isDeleted = try container.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
    }

    /// The members, ignoring pick order.
    var memberSet: Set<String> {
        Set(memberIDs)
    }

    // MARK: - Input

    static let maximumNameLength = 40

    /// The trimmed name, at most `maximumNameLength` characters.
    static func sanitizedName(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(maximumNameLength))
    }

    /// The first character (one emoji, flags and skin tones included), or `nil` when empty.
    static func sanitizedEmoji(_ text: String?) -> String? {
        guard let first = text?.trimmingCharacters(in: .whitespacesAndNewlines).first else { return nil }

        return String(first)
    }
}

/// A chip on the "Who's on the couch?" picker: a named preset or one of the last couches.
struct CouchChip: Hashable, Identifiable, Sendable {

    enum Kind: Hashable, Sendable {
        case preset
        case recent
    }

    let id: String
    let kind: Kind
    /// The members in pick order.
    let memberIDs: [String]
    /// The member names in pick order.
    let memberNames: [String]
    /// The stored preset, for `.preset` chips.
    let preset: CouchPreset?

    var memberSet: Set<String> {
        Set(memberIDs)
    }
}

/// Storage format, merge rules and chip building for couch presets.
///
/// Foundation only: this file is type-checked and unit-tested on Linux.
enum CouchPresetSync {

    /// DisplayPreferences id used as the store. Must never be an id jellyfin-web uses.
    static let displayPreferencesID = "swiftfin-couch-presets"
    /// DisplayPreferences client, shared with the audience watchlist.
    static let client = AudienceWatchlistSync.client
    /// Every key we own starts with this prefix. Other keys (server defaults) are never written back.
    static let ownedKeyPrefix = AudienceWatchlistSync.ownedKeyPrefix
    /// One key per preset: `sgw.p.<preset.id>`.
    static let presetKeyPrefix = "sgw.p."
    /// Tombstones older than this are pruned on the next write. Presets are few, so they are kept for long.
    static let tombstoneLifetime: TimeInterval = 365 * 24 * 60 * 60

    /// How many of the last couches are shown as chips.
    static let maximumRecentChips = 3
    /// How many of the last couches are remembered.
    static let maximumStoredRecents = 12

    static func key(forPresetID id: String) -> String {
        presetKeyPrefix + id
    }

    // MARK: - Coding

    static func encode(_ preset: CouchPreset) -> String? {
        guard let data = try? AudienceWatchlistSync.makeEncoder().encode(preset) else { return nil }

        return String(data: data, encoding: .utf8)
    }

    static func decodePreset(_ value: String) -> CouchPreset? {
        guard let data = value.data(using: .utf8) else { return nil }

        return try? AudienceWatchlistSync.makeDecoder().decode(CouchPreset.self, from: data)
    }

    /// Presets stored in one account's custom prefs, keyed by preset id. Undecodable values are skipped.
    static func presets(in customPrefs: [String: String?]) -> [String: CouchPreset] {
        var result: [String: CouchPreset] = [:]

        for (key, value) in customPrefs {
            guard key.hasPrefix(presetKeyPrefix), let value, let preset = decodePreset(value) else { continue }

            let id = String(key.dropFirst(presetKeyPrefix.count))
            guard preset.id == id else { continue }

            result[id] = newest(result[id], preset)
        }

        return result
    }

    // MARK: - Merge

    /// The winner of two copies of the same preset: newest `updatedAt`; on a tie the tombstone wins.
    static func newest(_ lhs: CouchPreset?, _ rhs: CouchPreset) -> CouchPreset {
        guard let lhs else { return rhs }

        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt ? lhs : rhs
        }
        if lhs.isDeleted != rhs.isDeleted {
            return lhs.isDeleted ? lhs : rhs
        }
        return lhs
    }

    /// Merges preset maps from several sources, by id, newest wins.
    static func merge(_ sources: [[String: CouchPreset]]) -> [String: CouchPreset] {
        var result: [String: CouchPreset] = [:]

        for source in sources {
            for (id, preset) in source {
                result[id] = newest(result[id], preset)
            }
        }

        return result
    }

    /// Non-deleted presets with members, sorted by name.
    static func visiblePresets(_ all: [String: CouchPreset]) -> [CouchPreset] {
        all.values
            .filter { $0.isDeleted == false && $0.memberIDs.isEmpty == false }
            .sorted { lhs, rhs in
                let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                if order != .orderedSame {
                    return order == .orderedAscending
                }
                return lhs.id < rhs.id
            }
    }

    /// `preset` with an `updatedAt` strictly newer than `existing`, even with a clock that's slightly behind.
    ///
    /// Rounded to whole milliseconds, the stored precision, so a local copy equals its stored copy.
    static func stamped(_ preset: CouchPreset, existing: CouchPreset?, now: Date) -> CouchPreset {
        var result = preset
        let now = roundedToMilliseconds(now)

        if let existing, existing.updatedAt >= now {
            result.updatedAt = roundedToMilliseconds(existing.updatedAt.addingTimeInterval(0.001))
        } else {
            result.updatedAt = now
        }

        return result
    }

    static func roundedToMilliseconds(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 * 1000).rounded() / 1000)
    }

    /// The tombstone stored when `preset` is deleted.
    static func makeTombstone(of preset: CouchPreset, now: Date) -> CouchPreset {
        var tombstone = stamped(preset, existing: preset, now: now)
        tombstone.isDeleted = true
        return tombstone
    }

    // MARK: - Writing

    /// The custom prefs to POST for one account, holding every preset in `merged`.
    ///
    /// - Keeps our other `sgw.` keys with non-nil values (server-owned keys are reset by the server anyway).
    /// - Replaces every preset key with the `merged` copy.
    /// - Prunes tombstones older than `tombstoneLifetime`.
    static func customPrefsForWriting(
        existing: [String: String?],
        merged: [String: CouchPreset],
        now: Date
    ) -> [String: String] {
        var result: [String: String] = [:]

        for (key, value) in existing {
            guard key.hasPrefix(ownedKeyPrefix), key.hasPrefix(presetKeyPrefix) == false, let value else { continue }

            result[key] = value
        }

        let cutoff = now.addingTimeInterval(-tombstoneLifetime)

        for (id, preset) in merged {
            if preset.isDeleted, preset.updatedAt < cutoff {
                continue
            }
            if let value = encode(preset) {
                result[key(forPresetID: id)] = value
            }
        }

        return result
    }

    /// Whether an account's stored presets differ from `merged`, ignoring tombstones that would be pruned.
    ///
    /// Compares the stored form, so a difference below the stored date precision never causes a write.
    static func needsWrite(stored: [String: CouchPreset], merged: [String: CouchPreset], now: Date) -> Bool {
        let cutoff = now.addingTimeInterval(-tombstoneLifetime)
        let expected = merged.filter { _, preset in
            !(preset.isDeleted && preset.updatedAt < cutoff)
        }

        return stored.mapValues(encode) != expected.mapValues(encode)
    }

    // MARK: - Recent couches

    /// A couch as stored in the local history: member ids in pick order, comma-joined.
    static func recentToken(_ memberIDs: [String]) -> String {
        memberIDs.joined(separator: ",")
    }

    static func recentMemberIDs(from token: String) -> [String] {
        token.split(separator: ",").map(String.init)
    }

    /// The history with `memberIDs` moved to the front. A couch with the same people in another order replaces the old one.
    static func recordingRecent(_ memberIDs: [String], in history: [String]) -> [String] {
        guard memberIDs.isEmpty == false else { return history }

        let members = Set(memberIDs)
        var result = history.filter { Set(recentMemberIDs(from: $0)) != members }
        result.insert(recentToken(memberIDs), at: 0)

        return Array(result.prefix(maximumStoredRecents))
    }

    /// The history without any couch of exactly these people.
    static func forgettingRecent(_ memberIDs: Set<String>, in history: [String]) -> [String] {
        history.filter { Set(recentMemberIDs(from: $0)) != memberIDs }
    }

    // MARK: - Chips

    /// The chips to show: every named preset whose members are all available, then up to
    /// `maximumRecentChips` of the last couches that are not a preset already.
    ///
    /// - Parameters:
    ///   - presets: The visible presets of the shown servers.
    ///   - recents: The local history, newest first, as member ids in pick order.
    ///   - usernames: The name of every user that can be picked right now, by id.
    ///   - serverIDs: The server of every user that can be picked right now, by id. Couches never mix servers.
    static func chips(
        presets: [CouchPreset],
        recents: [[String]],
        usernames: [String: String],
        serverIDs: [String: String]
    ) -> [CouchChip] {
        func isAvailable(_ memberIDs: [String]) -> Bool {
            guard let first = memberIDs.first, let serverID = serverIDs[first] else { return false }

            return memberIDs.allSatisfy { usernames[$0] != nil && serverIDs[$0] == serverID }
        }

        func names(_ memberIDs: [String]) -> [String] {
            memberIDs.compactMap { usernames[$0] }
        }

        var seen: Set<Set<String>> = []
        var chips: [CouchChip] = []

        for preset in presets where preset.isDeleted == false && isAvailable(preset.memberIDs) {
            seen.insert(preset.memberSet)
            chips.append(
                CouchChip(
                    id: "preset-\(preset.id)",
                    kind: .preset,
                    memberIDs: preset.memberIDs,
                    memberNames: names(preset.memberIDs),
                    preset: preset
                )
            )
        }

        var recentCount = 0

        for memberIDs in recents where recentCount < maximumRecentChips && isAvailable(memberIDs) {
            guard seen.insert(Set(memberIDs)).inserted else { continue }

            chips.append(
                CouchChip(
                    id: "recent-\(recentToken(memberIDs))",
                    kind: .recent,
                    memberIDs: memberIDs,
                    memberNames: names(memberIDs),
                    preset: nil
                )
            )
            recentCount += 1
        }

        return chips
    }

    /// Whether the chip row adds anything to the picker.
    ///
    /// The last couch is already pre-selected, so a single recent couch and no presets keeps the picker as it was.
    static func shouldShowChips(_ chips: [CouchChip]) -> Bool {
        chips.contains { $0.kind == .preset } || chips.count > 1
    }
}
