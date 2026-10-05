//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import Logging

// MARK: - Watchlist sync

/// Mirrors the audience of a "Who's it for?" entry into each person's own Seerr watchlist,
/// so Seerr (and its own watchlist sync to Jellyfin) stays in step with the household watchlist.
///
/// Shared by every place that tags a title: the item view, the poster menu,
/// the Watchlists screen and the Seerr detail screen.
@MainActor
extension SeerrService {

    /// Best effort: adds the title to the Seerr watchlist of everyone in `adding` and removes it
    /// from everyone in `removing`, one request per person, concurrently. Never throws.
    ///
    /// Acts by Jellyfin user id through `perform(asJellyfinUserID:)`: a person's own Quick Connect
    /// session when they have one, else the API key as them. People who can't act on Seerr are skipped
    /// (logged). Does nothing when Seerr isn't configured, without a TMDB id, or when both sets are empty.
    ///
    /// - Parameters:
    ///   - tmdbID: The TMDB id of the title. `nil` (a Jellyfin-only title) skips the sync.
    ///   - title: The title Seerr shows on the watchlist. Only used when adding.
    ///   - adding: Jellyfin user ids that should have the title on their Seerr watchlist.
    ///   - removing: Jellyfin user ids that should not. A person in both sets is added.
    func syncWatchlists(
        tmdbID: Int?,
        mediaType: SeerrMediaType,
        title: String?,
        adding: Set<String>,
        removing: Set<String>
    ) async {
        guard isConfigured, let tmdbID else { return }

        let removing = removing.subtracting(adding)
        guard adding.isNotEmpty || removing.isNotEmpty else { return }

        let watchlistTitle = title ?? ""

        // `SeerrService` is main actor isolated: the children run on the main actor,
        // but their network requests still overlap.
        await withTaskGroup(of: Void.self) { group in
            for jellyfinUserID in adding.union(removing) {
                let isAdding = adding.contains(jellyfinUserID)

                group.addTask { @MainActor in
                    await self.syncWatchlist(
                        jellyfinUserID: jellyfinUserID,
                        isAdding: isAdding,
                        tmdbID: tmdbID,
                        mediaType: mediaType,
                        title: watchlistTitle
                    )
                }
            }
        }
    }

    /// `syncWatchlists(tmdbID:mediaType:title:adding:removing:)` for a household watchlist entry.
    func syncWatchlists(
        for entry: AudienceWatchlistEntry,
        adding: Set<String>,
        removing: Set<String>
    ) async {
        await syncWatchlists(
            tmdbID: entry.tmdbID,
            mediaType: entry.kind == .movie ? .movie : .tv,
            title: entry.title,
            adding: adding,
            removing: removing
        )
    }

    private func syncWatchlist(
        jellyfinUserID: String,
        isAdding: Bool,
        tmdbID: Int,
        mediaType: SeerrMediaType,
        title: String
    ) async {
        do {
            try await perform(asJellyfinUserID: jellyfinUserID) { userClient in
                if isAdding {
                    try await userClient.addToWatchlist(
                        mediaType: mediaType,
                        tmdbID: tmdbID,
                        title: title
                    )
                } else {
                    try await userClient.removeFromWatchlist(
                        mediaType: mediaType,
                        tmdbID: tmdbID
                    )
                }
            }
        } catch {
            Logger.swiftfin().warning(
                "Failed to sync a Seerr watchlist",
                metadata: [
                    "jellyfinUserID": .string(jellyfinUserID),
                    "tmdbID": .string(String(tmdbID)),
                    "isAdding": .string(String(isAdding)),
                    "error": .string(error.localizedDescription),
                ]
            )
        }
    }
}
