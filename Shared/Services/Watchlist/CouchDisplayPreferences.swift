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

/// Reads and writes the custom prefs of a couch DisplayPreferences row (client `swiftfin-couch`).
///
/// Shared by the audience watchlist (`swiftfin-couch-watchlist`) and the couch presets (`swiftfin-couch-presets`).
enum CouchDisplayPreferences {

    /// GET with our own lenient DTO: the SDK's `DisplayPreferencesDto` fails on a fresh row's `"tvhome": null`.
    static func fetchCustomPrefs(
        displayPreferencesID: String,
        userID: String,
        client: JellyfinClient
    ) async throws -> [String: String?] {
        let request = Request<CouchPrefsDTO>(
            path: "/DisplayPreferences/\(displayPreferencesID)",
            query: [
                ("userId", userID),
                ("client", AudienceWatchlistSync.client),
            ]
        )

        let response = try await client.send(request)
        return response.value.customPrefs
    }

    /// POST replaces the whole map, so `customPrefs` must be the complete set of our keys.
    /// The other fields are the server defaults, sent explicitly because the body is a full DTO.
    static func postCustomPrefs(
        _ customPrefs: [String: String],
        displayPreferencesID: String,
        userID: String,
        client: JellyfinClient
    ) async throws {
        let body = DisplayPreferencesDto(
            client: AudienceWatchlistSync.client,
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
            client: AudienceWatchlistSync.client,
            body
        )

        try await client.send(request)
    }
}
