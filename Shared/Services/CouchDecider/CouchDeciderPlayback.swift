//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI
import Logging

/// Turns a decider card into something to play.
///
/// Mirrors the item screen's play button (`ItemContentGroupProvider`):
/// a show plays the user's next-up episode, or its first available episode.
@MainActor
enum CouchDeciderPlayback {

    private static let logger = Logger.swiftfin()

    /// Movie/episode → full item; series → the primary's next-up (or first available) episode, full item.
    ///
    /// - Throws: When a request fails, or when a show has no available episode.
    static func playbackItem(for item: BaseItemDto, session: UserSession) async throws -> BaseItemDto {
        guard item.type == .series else {
            return try await item.getFullItem(userSession: session)
        }
        guard let seriesID = item.id else {
            throw ErrorMessage(L10n.unknownError)
        }

        do {
            if let nextUp = try await nextUpEpisode(seriesID: seriesID, session: session) {
                return try await nextUp.getFullItem(userSession: session)
            }
        } catch {
            // Fall back to the first episode: a new show usually has no next up anyway.
            logger.error("Couch decider: could not get the next up episode: \(error.localizedDescription)")
        }

        guard let firstEpisode = try await firstAvailableEpisode(seriesID: seriesID, session: session) else {
            throw ErrorMessage(L10n.noEpisodesAvailable)
        }

        return try await firstEpisode.getFullItem(userSession: session)
    }

    /// `.videoPlayer(provider:queue:)`. Registers the player manager: call right before `router.route(to:)`.
    ///
    /// Episodes get an `EpisodeMediaPlayerQueue`, so the next episode can autoplay.
    /// Returns `nil` when the item can't be played.
    static func route(for playbackItem: BaseItemDto, session: UserSession) -> NavigationRoute? {
        guard let provider = playbackItem.getPlaybackItemProvider(userSession: session) else {
            logger.error("Couch decider: no playback provider for the item")
            return nil
        }

        let queue: (any MediaPlayerQueue)? = playbackItem.type == .episode ?
            EpisodeMediaPlayerQueue(episode: playbackItem) : nil

        return NavigationRoute.videoPlayer(provider: provider, queue: queue)
    }

    // MARK: - Helpers

    /// The user's next-up episode of the show, skipping missing episodes.
    private static func nextUpEpisode(seriesID: String, session: UserSession) async throws -> BaseItemDto? {
        var parameters = Paths.GetNextUpParameters()
        parameters.seriesID = seriesID
        parameters.userID = session.user.id

        let request = Paths.getNextUp(parameters: parameters)
        let response = try await session.client.send(request)

        return response.value.items?.first { !$0.isMissing }
    }

    /// The show's first available episode, preferring regular seasons over specials (season 0).
    private static func firstAvailableEpisode(seriesID: String, session: UserSession) async throws -> BaseItemDto? {
        var parameters = Paths.GetItemsParameters()
        parameters.includeItemTypes = [.episode]
        parameters.isMissing = false
        parameters.isRecursive = true
        parameters.limit = 50
        parameters.parentID = seriesID
        parameters.sortBy = [.parentIndexNumber, .indexNumber]
        parameters.sortOrder = [.ascending]
        parameters.userID = session.user.id

        let request = Paths.getItems(parameters: parameters)
        let response = try await session.client.send(request)
        let episodes = (response.value.items ?? []).filter { !$0.isMissing }

        return episodes.first { ($0.parentIndexNumber ?? 0) > 0 } ?? episodes.first
    }
}
