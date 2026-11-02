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

/// Keeps audio sync fixes on the server, per file, so they follow the user to every device.
///
/// Stored in the Jellyfin DisplayPreferences of the user (id `couchfin-avsync`, client `couchfin`),
/// one custom pref per media source: `avsync.<mediaSourceID>` → `AVSyncCorrection.encoded`.
/// Writes are read-modify-write, so the fixes for other files survive.
enum AVSyncStore {

    /// DisplayPreferences id used as the store. Must never be an id jellyfin-web uses.
    static let displayPreferencesID = "couchfin-avsync"
    /// DisplayPreferences client (≤ 32 characters).
    static let client = "couchfin"
    static let keyPrefix = "avsync."

    static func key(forMediaSourceID mediaSourceID: String) -> String {
        keyPrefix + mediaSourceID
    }

    // MARK: - Read

    /// The saved fix for a file, if any.
    static func load(mediaSourceID: String, userSession: UserSession) async throws -> AVSyncCorrection? {
        let customPrefs = try await fetchCustomPrefs(
            userID: userSession.user.id,
            client: userSession.client
        )

        guard let value = customPrefs[key(forMediaSourceID: mediaSourceID)] ?? nil else { return nil }

        return AVSyncCorrection(encoded: value)
    }

    // MARK: - Write

    /// Saves (or with `nil`, removes) the fix for a file.
    ///
    /// The user's own row must succeed. The other people on the couch get a copy on a best-effort basis,
    /// so the fix is there when they watch the file on their own.
    static func save(
        _ correction: AVSyncCorrection?,
        mediaSourceID: String,
        userSession: UserSession
    ) async throws {
        let prefKey = key(forMediaSourceID: mediaSourceID)

        try await write(correction?.encoded, key: prefKey, userID: userSession.user.id, client: userSession.client)

        for member in userSession.memberSessions {
            try? await write(correction?.encoded, key: prefKey, userID: member.user.id, client: member.client)
        }
    }

    private static func write(
        _ value: String?,
        key: String,
        userID: String,
        client: JellyfinClient
    ) async throws {
        var customPrefs = try await fetchCustomPrefs(userID: userID, client: client)
            .compactMapValues { $0 }

        if let value {
            guard customPrefs[key] != value else { return }

            customPrefs[key] = value
        } else {
            guard customPrefs[key] != nil else { return }

            customPrefs.removeValue(forKey: key)
        }

        try await postCustomPrefs(customPrefs, userID: userID, client: client)
    }

    // MARK: - Requests

    /// GET with the lenient DTO: the SDK's `DisplayPreferencesDto` fails on a fresh row's `"tvhome": null`.
    private static func fetchCustomPrefs(
        userID: String,
        client: JellyfinClient
    ) async throws -> [String: String?] {
        let request = Request<CouchPrefsDTO>(
            path: "/DisplayPreferences/\(displayPreferencesID)",
            query: [
                ("userId", userID),
                ("client", Self.client),
            ]
        )

        let response = try await client.send(request)
        return response.value.customPrefs
    }

    /// POST replaces the whole map, so `customPrefs` must be the complete set.
    /// The other fields are the server defaults, sent explicitly because the body is a full DTO.
    private static func postCustomPrefs(
        _ customPrefs: [String: String],
        userID: String,
        client: JellyfinClient
    ) async throws {
        let body = DisplayPreferencesDto(
            client: Self.client,
            customPrefs: customPrefs,
            id: displayPreferencesID,
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
            displayPreferencesID: displayPreferencesID,
            userID: userID,
            client: Self.client,
            body
        )

        try await client.send(request)
    }
}
