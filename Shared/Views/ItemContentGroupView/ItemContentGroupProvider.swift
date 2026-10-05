//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Get
import JellyfinAPI
import SwiftUI

final class ItemContentGroupProvider: ViewModel, ContentGroupProvider {

    @Published
    private(set) var item: BaseItemDto
    @Published
    private(set) var localTrailers: [BaseItemDto] = []
    @Published
    private(set) var mediaPlayerItemProvider: MediaPlayerItemProvider?
    @Published
    private(set) var randomBackdropItem: BaseItemDto?

    /// Where everyone on a group couch is in the item Play would start,
    /// fetched after the page loads. `nil` on a solo couch.
    @Published
    private(set) var couchResumePlan: CouchResumePlan?

    @Published
    var isPresentingDeleteConfirmation = false

    /// On a group couch: asks whether "Mark unwatched" is for everyone or just the primary user.
    @Published
    var isPresentingUnplayedChoice = false

    let id: String

    private var couchResumeTask: Task<Void, Never>?

    var displayTitle: String {
        item.displayTitle
    }

    /// Whether more than one person is on the couch.
    var isCouchGroup: Bool {
        userSession?.couch.isGroup == true
    }

    init(item: BaseItemDto) {
        self.id = item.id ?? "Unknown"
        self.item = item
        super.init()
    }

    init(id: String) {
        self.id = id
        self.item = .init(id: id)
        super.init()
    }

    func makeGroups(environment: Empty) async throws -> [any ContentGroup] {
        let userSession = try requireUserSession()
        let fullItem = try await item.getFullItem(userSession: userSession, sendNotification: true)
        let newMediaPlayerItemProvider = try await resolveMediaPlayerItemProvider(
            for: fullItem,
            userSession: userSession
        )
        let newLocalTrailers = try? await localTrailers(for: fullItem)
        let newRandomBackdropItem = try? await randomBackdropItem(for: fullItem)

        item = fullItem
        localTrailers = newLocalTrailers ?? []
        mediaPlayerItemProvider = newMediaPlayerItemProvider
        randomBackdropItem = newRandomBackdropItem

        refreshCouchResumePlan(for: newMediaPlayerItemProvider?.item, userSession: userSession)

        return try await _makeGroups(
            item: fullItem,
            itemID: id
        )
    }

    @ContentGroupBuilder
    private func _makeGroups(item: BaseItemDto, itemID: String) async throws -> [any ContentGroup] {

        if let birthday = item.birthday?.formatted(date: .long, time: .omitted) {
            LabeledContentGroup(
                L10n.born,
                value: birthday
            )
        }

        if let deathday = item.deathday?.formatted(date: .long, time: .omitted) {
            LabeledContentGroup(
                L10n.died,
                value: deathday
            )
        }

        if let birthplace = item.birthplace {
            LabeledContentGroup(
                L10n.birthplace,
                value: birthplace
            )
        }

        switch item.type {
        case .season, .series:
            SeriesEpisodeContentGroup(
                parent: item,
                playButtonItem: mediaPlayerItemProvider?.item
            )

        default:
            []
        }

        if let genres = item.itemGenres, genres.isNotEmpty {
            PillGroup(
                displayTitle: L10n.genres,
                id: "genres",
                elements: genres
            ) { router, element in
                router.route(
                    to: .contentGroup(
                        provider: ItemTypeContentGroupProvider(
                            itemTypes: [
                                BaseItemKind.movie,
                                .series,
                                .boxSet,
                                .episode,
                                .musicVideo,
                                .video,
                                .liveTvProgram,
                                .tvChannel,
                                .person,
                            ],
                            parent: BaseItemDto(name: element.displayTitle),
                            environment: .init(filters: .init(genres: [element]))
                        )
                    )
                )
            }
        }

        if let studios = item.studios, studios.isNotEmpty {
            PillGroup(
                displayTitle: L10n.studios,
                id: "studios",
                elements: studios
            ) { router, element in
                router.route(
                    to: .contentGroup(
                        provider: ItemTypeContentGroupProvider(
                            itemTypes: [
                                BaseItemKind.movie,
                                .series,
                                .boxSet,
                                .episode,
                                .musicVideo,
                                .video,
                                .liveTvProgram,
                                .tvChannel,
                                .person,
                            ],
                            parent: BaseItemDto(id: element.id, name: element.displayTitle, type: .studio)
                        )
                    )
                )
            }
        }

        switch item.type {
        case .movie:
            if item.partCount ?? 0 > 1 {
                PosterGroup(
                    id: "additional-parts",
                    library: AdditionalPartsLibrary(itemID: itemID),
                    posterDisplayType: .landscape,
                    posterSize: .small
                )
            }

        case .boxSet, .person, .musicArtist:
            try await ItemTypeContentGroupProvider(
                itemTypes: BaseItemKind.supportedCases
                    .appending(.episode)
                    .appending(.person),
                parent: item
            )
            .makeGroups(environment: .default)

        case .series:
            try await ItemTypeContentGroupProvider(
                itemTypes: [.season],
                parent: item
            )
            .makeGroups(environment: .default)

        case .channel, .liveTvChannel, .tvChannel:
            PosterGroup(
                id: "channel-programs",
                library: ChannelScheduleLibrary(channel: item),
                posterDisplayType: .landscape,
                posterSize: .small
            )

        default: []
        }

        if item.type == .episode {
            PosterGroup(
                library: StaticLibrary(
                    title: L10n.season,
                    id: "seasons",
                    elements: [BaseItemDto(
                        id: item.seasonID,
                        imageTags: item.parentPrimaryImageItemID == item.seasonID
                            ? item.parentPrimaryImageTag.map { [ImageType.primary.rawValue: $0] }
                            : nil,
                        name: item.seasonName,
                        parentBackdropImageTags: item.parentBackdropImageTags,
                        parentBackdropItemID: item.parentBackdropItemID,
                        parentThumbImageTag: item.parentThumbImageTag,
                        parentThumbItemID: item.parentThumbItemID,
                        seriesID: item.seriesID,
                        seriesName: item.seriesName,
                        seriesPrimaryImageTag: item.seriesPrimaryImageTag,
                        seriesThumbImageTag: item.seriesThumbImageTag,
                        type: .season
                    )]
                ),
                posterSize: .small,
                environment: .init(isHeaderButtonEnabled: false)
            )
        }

        if let castAndCrew = item.mergedPeople, castAndCrew.isNotEmpty {
            PosterGroup(
                id: "cast-and-crew",
                library: StaticLibrary(
                    title: L10n.castAndCrew.localizedCapitalized,
                    id: "cast-and-crew",
                    elements: castAndCrew
                ),
                posterDisplayType: .portrait,
                posterSize: .small
            )
        }

        PosterGroup(
            id: "special-features",
            library: SpecialFeaturesLibrary(itemID: itemID),
            posterDisplayType: .landscape,
            posterSize: .small
        )

        if Defaults[.Customization.shouldShowRecommendations] {
            PosterGroup(
                id: "similar-items",
                library: SimilarItemsLibrary(itemID: itemID, itemType: item.type),
                posterDisplayType: .landscape,
                posterSize: .small
            )
        }

        AboutItemGroup(
            displayTitle: L10n.about,
            id: "about",
            item: item
        )
    }

    func toggleIsFavorite() async {
        let beforeIsFavorite = item.userData?.isFavorite ?? false

        item.userData?.isFavorite = !beforeIsFavorite
        do {
            try await setIsFavorite(!beforeIsFavorite)
        } catch {
            item.userData?.isFavorite = beforeIsFavorite
        }
    }

    func toggleIsPlayed() async {
        let beforeIsPlayed = item.userData?.isPlayed ?? false

        item.userData?.isPlayed = !beforeIsPlayed
        do {
            try await setIsPlayed(!beforeIsPlayed)
        } catch {
            item.userData?.isPlayed = beforeIsPlayed
        }
    }

    /// Marks the item played or unplayed on a group couch, then toasts who was updated.
    ///
    /// - Parameter forEveryone: Also mirror the change to every other member on the couch.
    ///   When `false`, only the primary user is changed ("Just Tuur").
    func setIsPlayedOnCouch(_ isPlayed: Bool, forEveryone: Bool) async {
        guard let userSession, let itemID = item.id else { return }

        let beforeIsPlayed = item.userData?.isPlayed ?? false

        item.userData?.isPlayed = isPlayed
        do {
            try await sendIsPlayed(isPlayed, itemID: itemID)
        } catch {
            item.userData?.isPlayed = beforeIsPlayed
            logger.error(
                "Couch: failed to mark item \(isPlayed ? "played" : "unplayed")",
                metadata: [
                    "itemID": .stringConvertible(itemID),
                    "error": .stringConvertible(error.localizedDescription),
                ]
            )
            CouchPlayedFeedback.presentPrimaryFailure(in: userSession)
            return
        }

        // The server just reset resume points: never offer a stale one. The next refresh rebuilds it.
        clearCouchResumePlan()

        if forEveryone {
            await CouchPlayedFeedback.mirror(itemID: itemID, isPlayed: isPlayed, in: userSession)
        } else {
            CouchPlayedFeedback.presentPrimaryOnly(isPlayed: isPlayed, in: userSession)
        }
    }

    enum PlaybackSelection {
        case mediaSource(MediaSourceInfo?)
        case audioStreamIndex(Int?)
        case subtitleStreamIndex(Int?)
        case bitrate(PlaybackBitrate)
    }

    func select(_ selection: PlaybackSelection) {
        guard let provider = mediaPlayerItemProvider, let userSession else { return }

        var mediaSource = provider.mediaSource
        var audioStreamIndex = provider.audioStreamIndex
        var subtitleStreamIndex = provider.subtitleStreamIndex
        var requestedBitrate = provider.requestedBitrate

        switch selection {
        case let .mediaSource(source):
            mediaSource = source
            audioStreamIndex = nil
            subtitleStreamIndex = nil

        case let .audioStreamIndex(index):
            audioStreamIndex = index

        case let .subtitleStreamIndex(index):
            subtitleStreamIndex = index

        case let .bitrate(bitrate):
            requestedBitrate = bitrate
        }

        mediaPlayerItemProvider = provider.item.getPlaybackItemProvider(
            userSession: userSession,
            mediaSource: mediaSource,
            audioStreamIndex: audioStreamIndex,
            subtitleStreamIndex: subtitleStreamIndex,
            requestedBitrate: requestedBitrate
        )
    }

    private func resolveMediaPlayerItemProvider(
        for item: BaseItemDto,
        userSession: UserSession
    ) async throws -> MediaPlayerItemProvider? {
        let playbackItem: BaseItemDto? = switch item.type {
        case .series:
            if let nextUp = try await nextUpItem(for: item) {
                nextUp
            } else if let resumeItem = try await resumeItem(for: item) {
                resumeItem
            } else {
                try await firstAvailableItem(for: item)
            }

        case .season:
            if let resumeItem = try await resumeItem(for: item) {
                resumeItem
            } else {
                try await firstAvailableItem(for: item)
            }

        default:
            item.isPlayable ? item : nil
        }

        guard let playbackItem else { return nil }

        let fullPlaybackItem = if item.type == .series || item.type == .season {
            try await playbackItem.getFullItem(userSession: userSession)
        } else {
            playbackItem
        }

        return fullPlaybackItem.getPlaybackItemProvider(userSession: userSession)
    }

    private func nextUpItem(for item: BaseItemDto) async throws -> BaseItemDto? {
        var parameters = Paths.GetNextUpParameters()
        parameters.seriesID = item.id

        let request = Paths.getNextUp(parameters: parameters)
        let response = try await send(request)

        guard let item = response.value.items?.first, !item.isMissing else {
            return nil
        }

        return item
    }

    private func resumeItem(for item: BaseItemDto) async throws -> BaseItemDto? {
        var parameters = Paths.GetResumeItemsParameters()
        parameters.limit = 1
        parameters.parentID = item.id

        let request = Paths.getResumeItems(parameters: parameters)
        let response = try await send(request)

        return response.value.items?.first
    }

    private func firstAvailableItem(for item: BaseItemDto) async throws -> BaseItemDto? {
        var parameters = Paths.GetItemsParameters()
        parameters.includeItemTypes = [.episode]
        parameters.isMissing = false
        parameters.isRecursive = true
        parameters.limit = 1
        parameters.parentID = item.id
        parameters.sortOrder = [.ascending]

        let request = Paths.getItems(parameters: parameters)
        let response = try await send(request)

        return response.value.items?.first
    }

    private func localTrailers(for item: BaseItemDto) async throws -> [BaseItemDto] {
        guard let itemID = item.id else { return [] }

        let request = try Paths.getLocalTrailers(itemID: itemID, userID: authenticatedUser.id)
        let response = try await send(request)

        return response.value
    }

    private func randomBackdropItem(for item: BaseItemDto) async throws -> BaseItemDto? {
        guard item.type == .person || item.type == .musicArtist || item.type == .boxSet else {
            return nil
        }

        var parameters = Paths.GetItemsParameters()
        parameters.includeItemTypes = [.movie, .series]
        parameters.isRecursive = true
        parameters.limit = 1
        parameters.sortBy = [.random]
        parameters.userID = try authenticatedUser.id

        switch item.libraryType {
        case .boxSet, .collectionFolder, .userView:
            parameters.parentID = item.id
        case .person:
            parameters.personIDs = item.id.map { [$0] }
        default:
            parameters.parentID = item.id
        }

        let request = Paths.getItems(parameters: parameters)
        let response = try await send(request)

        return response.value.items?.first
    }

    private func setIsPlayed(_ isPlayed: Bool) async throws {
        guard let itemID = item.id else { return }

        try await sendIsPlayed(isPlayed, itemID: itemID)
        userSession?.couchPlaybackService.mirrorPlayed(itemID: itemID, isPlayed: isPlayed)
    }

    /// Marks the item played or unplayed for the primary user only.
    private func sendIsPlayed(_ isPlayed: Bool, itemID: String) async throws {
        let request: Request<UserItemDataDto> = if isPlayed {
            try Paths.markPlayedItem(
                itemID: itemID,
                userID: authenticatedUser.id
            )
        } else {
            try Paths.markUnplayedItem(
                itemID: itemID,
                userID: authenticatedUser.id
            )
        }

        let response = try await send(request)
        Notifications[.itemUserDataDidChange].post(response.value)
        Notifications[.itemShouldRefreshMetadata].post(itemID)
    }

    // MARK: - Couch resume points

    /// Drops the couch resume plan until the next refresh, e.g. once playback starts:
    /// the positions it was built from are about to change, and the item page
    /// isn't refreshed when the player closes.
    func clearCouchResumePlan() {
        guard couchResumePlan != nil || couchResumeTask != nil else { return }

        couchResumeTask?.cancel()
        couchResumeTask = nil
        couchResumePlan = nil
    }

    /// Fetches every other member's user data for the item Play would start, in the
    /// background, and builds `couchResumePlan`. Clears it on a solo couch.
    private func refreshCouchResumePlan(for playbackItem: BaseItemDto?, userSession: UserSession) {
        couchResumeTask?.cancel()
        couchResumeTask = nil

        guard userSession.couch.isGroup,
              let playbackItem,
              let itemID = playbackItem.id
        else {
            couchResumePlan = nil
            return
        }

        let members = userSession.memberSessions

        guard members.isNotEmpty else {
            couchResumePlan = nil
            return
        }

        // The primary user's own position, as the Play button shows it.
        let primary = CouchResumePlan.Member(
            name: userSession.user.username,
            positionTicks: playbackItem.userData?.playbackPositionTicks,
            isPlayed: playbackItem.userData?.isPlayed,
            isPrimary: true
        )

        // Keep a plan for the same item while refreshing, so the hint doesn't flicker.
        if couchResumePlan?.itemID != itemID {
            couchResumePlan = nil
        }

        couchResumeTask = Task { [weak self] in
            guard let self else { return }

            let others = await self.memberResumePoints(itemID: itemID, members: members)

            guard !Task.isCancelled else { return }

            self.couchResumePlan = CouchResumePlan(itemID: itemID, members: [primary] + others)
        }
    }

    /// Every member's own position in the item, fetched concurrently, in couch order.
    ///
    /// Members whose fetch failed, including members who can't see the item (404), are left out.
    private func memberResumePoints(itemID: String, members: [UserSession]) async -> [CouchResumePlan.Member] {
        let fetched: [(Int, CouchResumePlan.Member?)] = await withTaskGroup(
            of: (Int, CouchResumePlan.Member?).self
        ) { group in
            for (index, member) in members.enumerated() {
                group.addTask { @MainActor in
                    do {
                        let userData = try await member.client
                            .send(Paths.getItemUserData(itemID: itemID, userID: member.user.id))
                            .value

                        return (
                            index,
                            CouchResumePlan.Member(
                                name: member.user.username,
                                positionTicks: userData.playbackPositionTicks,
                                isPlayed: userData.isPlayed,
                                isPrimary: false
                            )
                        )
                    } catch {
                        self.logger.warning(
                            "Couch: couldn't fetch a member's resume point",
                            metadata: [
                                "itemID": .stringConvertible(itemID),
                                "memberID": .stringConvertible(member.user.id),
                                "error": .stringConvertible(error.localizedDescription),
                            ]
                        )

                        return (index, nil)
                    }
                }
            }

            var results: [(Int, CouchResumePlan.Member?)] = []

            for await result in group {
                results.append(result)
            }

            return results
        }

        return fetched
            .sorted { $0.0 < $1.0 }
            .compactMap(\.1)
    }

    private func setIsFavorite(_ isFavorite: Bool) async throws {
        guard let itemID = item.id else { return }

        let request: Request<UserItemDataDto> = if isFavorite {
            try Paths.markFavoriteItem(
                itemID: itemID,
                userID: authenticatedUser.id
            )
        } else {
            try Paths.unmarkFavoriteItem(
                itemID: itemID,
                userID: authenticatedUser.id
            )
        }

        let response = try await send(request)
        Notifications[.itemUserDataDidChange].post(response.value)
        Notifications[.itemShouldRefreshMetadata].post(itemID)
    }
}
