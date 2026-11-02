//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import Get
import JellyfinAPI

/// An item that stuttered and should get a lighter copy on the server.
struct LighterCopyEntry: Codable, Hashable, Identifiable {

    /// The Jellyfin item ID.
    var id: String
    var name: String
    /// Why it stuttered, in words.
    var reason: String
    /// The copy that would play directly, in words.
    var target: String
    var diagnosis: PlaybackHealthDiagnosis
    var stalls: Int
    var updatedAt: Date
    /// The user that watched it.
    var reportedBy: String
    var device: String
}

/// The "Needs a lighter copy" list, stored per user in the Jellyfin DisplayPreferences
/// `playback-health` (client `couchfin`), one custom pref per item.
enum LighterCopyStore {

    static let displayPreferencesID = "playback-health"
    static let client = "couchfin"
    static let entryKeyPrefix = "ph."
    /// The most entries kept per user, newest first.
    static let maxEntries = 200

    // MARK: - Coding

    static func key(forItemID itemID: String) -> String {
        entryKeyPrefix + itemID
    }

    static func encode(_ entry: LighterCopyEntry) -> String? {
        let encoder = AudienceWatchlistSync.makeEncoder()
        guard let data = try? encoder.encode(entry) else { return nil }

        return String(data: data, encoding: .utf8)
    }

    static func decode(_ value: String) -> LighterCopyEntry? {
        guard let data = value.data(using: .utf8) else { return nil }

        return try? AudienceWatchlistSync.makeDecoder().decode(LighterCopyEntry.self, from: data)
    }

    /// Entries in one user's custom prefs. Undecodable values are skipped.
    static func entries(in customPrefs: [String: String?]) -> [LighterCopyEntry] {
        var result: [LighterCopyEntry] = []

        for (key, value) in customPrefs {
            guard key.hasPrefix(entryKeyPrefix), let value, let entry = decode(value) else { continue }

            result.append(entry)
        }

        return result
    }

    /// The custom prefs to POST: only our own keys, with `changes` applied (`nil` removes), capped to `maxEntries`.
    static func customPrefsForWriting(
        existing: [String: String?],
        changes: [String: LighterCopyEntry?]
    ) -> [String: String] {
        var entries: [String: LighterCopyEntry] = [:]

        for entry in self.entries(in: existing) {
            entries[entry.id] = entry
        }

        for (itemID, change) in changes {
            entries[itemID] = change
        }

        let kept = entries.values
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(maxEntries)

        var result: [String: String] = [:]

        for entry in kept {
            if let value = encode(entry) {
                result[key(forItemID: entry.id)] = value
            }
        }

        return result
    }

    /// Merges the lists of several users: one row per item, the newest report wins, stalls add up.
    static func merge(_ lists: [[LighterCopyEntry]]) -> [LighterCopyEntry] {
        var merged: [String: LighterCopyEntry] = [:]

        for entry in lists.joined() {
            guard var existing = merged[entry.id] else {
                merged[entry.id] = entry
                continue
            }

            let totalStalls = existing.stalls + entry.stalls

            if entry.updatedAt > existing.updatedAt {
                existing = entry
            }

            existing.stalls = totalStalls
            merged[entry.id] = existing
        }

        return merged.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: - Networking

    /// The custom prefs of one row: the lighter copy list by default, or the server facts next to it.
    static func fetchCustomPrefs(
        userID: String,
        client: JellyfinClient,
        preferencesID: String = LighterCopyStore.displayPreferencesID
    ) async throws -> [String: String?] {
        let request = Request<CouchPrefsDTO>(
            path: "/DisplayPreferences/\(preferencesID)",
            query: [
                ("userId", userID),
                ("client", Self.client),
            ]
        )

        let response = try await client.send(request)
        return response.value.customPrefs
    }

    static func postCustomPrefs(
        _ customPrefs: [String: String],
        userID: String,
        client: JellyfinClient,
        preferencesID: String = LighterCopyStore.displayPreferencesID
    ) async throws {
        let body = DisplayPreferencesDto(
            client: Self.client,
            customPrefs: customPrefs,
            id: preferencesID,
            isRememberIndexing: false,
            isRememberSorting: false,
            isShowBackdrop: true,
            isShowSidebar: false,
            primaryImageHeight: 250,
            primaryImageWidth: 250,
            scrollDirection: .horizontal,
            sortBy: "SortName",
            sortOrder: .ascending
        )

        let request = Paths.updateDisplayPreferences(
            displayPreferencesID: preferencesID,
            userID: userID,
            client: Self.client,
            body
        )

        try await client.send(request)
    }

    /// Read-modify-write of one user's list.
    static func apply(_ changes: [String: LighterCopyEntry?], userID: String, client: JellyfinClient) async throws {
        let existing = try await fetchCustomPrefs(userID: userID, client: client)
        let customPrefs = customPrefsForWriting(existing: existing, changes: changes)
        try await postCustomPrefs(customPrefs, userID: userID, client: client)
    }

    /// Every user's list, merged. Reading other users' lists needs an administrator; otherwise only the own list is read.
    static func allEntries(userSession: UserSession) async throws -> [LighterCopyEntry] {
        let client = userSession.client
        var userIDs = [userSession.user.id]

        if let users = try? await client.send(Paths.getUsers()).value {
            userIDs = users.compactMap(\.id)
        }

        var lists: [[LighterCopyEntry]] = []

        for userID in userIDs {
            if let customPrefs = try? await fetchCustomPrefs(userID: userID, client: client) {
                lists.append(entries(in: customPrefs))
            }
        }

        return merge(lists)
    }

    /// Removes an item from every user's list that has it.
    static func remove(itemID: String, userSession: UserSession) async throws {
        let client = userSession.client
        var userIDs = [userSession.user.id]

        if let users = try? await client.send(Paths.getUsers()).value {
            userIDs = users.compactMap(\.id)
        }

        for userID in userIDs {
            guard let customPrefs = try? await fetchCustomPrefs(userID: userID, client: client),
                  customPrefs[key(forItemID: itemID)] != nil
            else { continue }

            try await apply([itemID: nil], userID: userID, client: client)
        }
    }
}
