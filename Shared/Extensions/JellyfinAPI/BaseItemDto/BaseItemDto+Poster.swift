//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Algorithms
import FactoryKit
import Foundation
import Get
import JellyfinAPI
import SwiftUI

extension BaseItemDto: Poster {

    struct Environment: WithDefaultValue, WithImageSourceOptions, WithViewContext {

        var maxWidth: CGFloat?
        var maxHeight: CGFloat?
        var quality: Int?
        var useParent: Bool = false
        var viewContext: ViewContext = .init()

        static var `default`: Self {
            .init()
        }
    }

    func resolveEnvironment(_ environment: EnvironmentValues) -> Environment {
        let viewContext = environment.viewContext

        return .init(
            useParent: viewContext.contains(.isThumb) && environment.posterConfiguration.useSeriesLandscapeBackdrop,
            viewContext: viewContext
        )
    }

    var preferredPosterDisplayType: PosterDisplayType {
        type?.preferredPosterDisplayType ?? .portrait
    }

    var subtitle: String? {
        switch type {
        case .episode:
            seasonEpisodeLabel
        case .person:
            people?.first?.displayRole
        case .video:
            extraType?.displayTitle
        default:
            nil
        }
    }

    var systemImage: String {
        switch type {
        case .audio, .musicAlbum:
            "music.note"
        case .boxSet:
            "film.stack"
        case .channel, .tvChannel, .liveTvChannel, .program:
            "tv"
        case .episode, .movie, .season, .series, .video:
            "film"
        case .collectionFolder, .folder, .userView:
            "folder.fill"
        case .musicVideo:
            "music.note.tv.fill"
        case .person:
            "person.fill"
        default:
            "circle"
        }
    }

    @ViewBuilder
    var posterLabel: some View {
        BaseItemDtoPosterLabel(item: self)
    }

    @ViewBuilder
    var posterContextMenu: some View {
        BaseItemDtoPosterContextMenu(item: self)
    }

    @ViewBuilder
    func posterOverlay(for displayType: PosterDisplayType) -> some View {
        ZStack {
            PosterIndicatorsOverlay(
                item: self,
                posterDisplayType: displayType
            )

            PosterSelectionOverlay()
        }
    }

    func imageSources(
        for displayType: PosterDisplayType,
        environment: Environment
    ) -> [ImageSource] {
        @ImageSourceBuilder
        var sources: [ImageSource] {
            let isLandscape = displayType == .landscape
            let preferThumb = isLandscape && environment.viewContext.contains(.isThumb)
            let inheritLandscape = !isLandscape || type != .episode || environment.useParent
            let isProgram = type == .program || type == .liveTvProgram || type == .tvProgram

            if isLandscape, environment.viewContext.contains(.isBackdrop) {
                if type == .episode {
                    imageSource(.backdrop, itemID: parentBackdropItemID, tag: parentBackdropImageTags?.first, environment: environment)
                }

                imageSource(.backdrop, itemID: id, environment: environment)
            }

            // Program squares represent the channel in the guide.
            if displayType == .square, isProgram {
                imageSource(.primary, itemID: channelID, tag: channelPrimaryImageTag, environment: environment)
            }

            if preferThumb {
                imageSource(.thumb, itemID: id, environment: environment)

                if inheritLandscape {
                    imageSource(.thumb, itemID: seriesID, tag: seriesThumbImageTag, environment: environment)
                    imageSource(.thumb, itemID: parentThumbItemID, tag: parentThumbImageTag, environment: environment)
                }
            }

            if isLandscape {
                let preferPrimary: Bool = if let primaryImageAspectRatio, primaryImageAspectRatio > 0 {
                    primaryImageAspectRatio >= 1.33
                } else {
                    switch type {
                    case .collectionFolder, .episode, .folder, .musicVideo, .userView, .video:
                        true
                    default:
                        false
                    }
                }

                if preferThumb || !preferPrimary {
                    imageSource(.backdrop, itemID: id, environment: environment)
                }

                if type == .season || (type == .episode && environment.useParent) {
                    imageSource(.backdrop, itemID: parentBackdropItemID, tag: parentBackdropImageTags?.first, environment: environment)
                }
            } else if type == .episode {
                // A portrait episode card uses its season/series poster when available.
                imageSource(.primary, itemID: parentPrimaryImageItemID, tag: parentPrimaryImageTag, environment: environment)
                imageSource(.primary, itemID: seriesID, tag: seriesPrimaryImageTag, environment: environment)
            }

            imageSource(.primary, itemID: id, environment: environment)

            // Never substitute a parent portrait for an episode's landscape still.
            if type != .episode || !isLandscape {
                imageSource(.primary, itemID: seriesID, tag: seriesPrimaryImageTag, environment: environment)
                imageSource(.primary, itemID: parentPrimaryImageItemID, tag: parentPrimaryImageTag, environment: environment)
            }

            imageSource(.primary, itemID: albumID, tag: albumPrimaryImageTag, environment: environment)

            if type == .season {
                imageSource(.thumb, itemID: id, environment: environment)
            }

            imageSource(.backdrop, itemID: id, environment: environment)
            imageSource(.thumb, itemID: id, environment: environment)

            if inheritLandscape {
                imageSource(.thumb, itemID: seriesID, tag: seriesThumbImageTag, environment: environment)
                imageSource(.thumb, itemID: parentThumbItemID, tag: parentThumbImageTag, environment: environment)
                imageSource(.backdrop, itemID: parentBackdropItemID, tag: parentBackdropImageTags?.first, environment: environment)
            }

            if isProgram {
                imageSource(.primary, itemID: channelID, tag: channelPrimaryImageTag, environment: environment)
            }
        }

        return Array(sources.uniqued())
    }

    @ViewBuilder
    func transform(image: Image, displayType: PosterDisplayType) -> some View {
        switch type {
        case .channel, .tvChannel:
            ContainerRelativeView(ratio: 0.95) {
                image
                    .aspectRatio(contentMode: .fit)
            }

        case .program:
            if displayType == .square {
                ContainerRelativeView(ratio: 0.95) {
                    image
                        .aspectRatio(contentMode: .fit)
                }
            } else {
                image
                    .aspectRatio(contentMode: .fill)
            }

        default:
            image
                .aspectRatio(contentMode: .fill)
        }
    }
}

private struct BaseItemDtoPosterContextMenu: View {

    @InjectedObject(\.audienceWatchlistStore)
    private var audienceStore: AudienceWatchlistStore

    @Router
    private var router

    @State
    private var item: BaseItemDto

    init(item: BaseItemDto) {
        self.item = item
    }

    private var isFavorite: Bool {
        item.userData?.isFavorite == true
    }

    private var isPlayed: Bool {
        item.userData?.isPlayed == true
    }

    /// "Mark watched for everyone" on a group couch. A context menu can't present a
    /// dialog, so unlike the item view, unwatched doesn't ask "everyone or just me".
    private var playedTitle: String {
        if Container.shared.currentUserSession()?.couch.isGroup == true {
            isPlayed ? L10n.CouchItem.markUnwatchedForEveryone : L10n.CouchItem.markWatchedForEveryone
        } else {
            isPlayed ? L10n.markAsUnplayed : L10n.markAsPlayed
        }
    }

    /// The watchlist entry this item is tagged with, ignoring an entry without anyone in it.
    private var audienceEntry: AudienceWatchlistEntry? {
        guard let entry = AudienceWatchlistActions.entry(for: item, in: audienceStore),
              entry.audience.isNotEmpty
        else { return nil }

        return entry
    }

    /// "Who's it for?" when untagged; "For Sam & Lisa…" plus "Remove from watchlist" when tagged.
    /// Same icon pair as the item view's `ItemActionButton.audience`.
    @ViewBuilder
    private var audienceButtons: some View {
        if let audienceEntry {
            let sentence = AudienceLabel.sentence(
                audience: audienceEntry.audience,
                users: AudienceWatchlistActions.serverUsers()
            )

            Button(L10n.Audience.editAudience(sentence), systemImage: ItemActionButton.audience.systemImage) {
                router.route(to: .audiencePicker(item: item))
            }

            Button(L10n.Audience.removeFromWatchlist, systemImage: "bookmark.slash", role: .destructive) {
                AudienceWatchlistActions.perform(.removed, item: item, completion: nil)
            }
        } else {
            Button(L10n.Audience.whosItFor, systemImage: ItemActionButton.audience.secondarySystemImage) {
                router.route(to: .audiencePicker(item: item))
            }
        }
    }

    var body: some View {
        if let itemID = item.id {
            Button(L10n.goToItem, systemImage: "info.circle") {
                router.route(to: .item(id: itemID))
            }
        }

        if item.type == .episode, let seriesID = item.seriesID {
            Button(L10n.goToSeries, systemImage: "tv") {
                router.route(to: .item(id: seriesID))
            }
        }

        if item.canBePlayed {
            Button(playedTitle, systemImage: isPlayed ? "circle" : "checkmark.circle") {
                Task {
                    await toggleIsPlayed()
                }
            }
        }

        if item.id != nil {
            Button(isFavorite ? L10n.removeFromFavorites : L10n.addToFavorites, systemImage: isFavorite ? "heart.slash" : "heart") {
                Task {
                    await toggleIsFavorite()
                }
            }
        }

        if AudienceWatchlistActions.supports(item) {
            audienceButtons
        }
    }

    @MainActor
    private func toggleIsPlayed() async {
        let beforeIsPlayed = item.userData?.isPlayed ?? false

        item.userData?.isPlayed = !beforeIsPlayed
        do {
            try await setIsPlayed(!beforeIsPlayed)
        } catch {
            item.userData?.isPlayed = beforeIsPlayed
        }
    }

    @MainActor
    private func toggleIsFavorite() async {
        let beforeIsFavorite = item.userData?.isFavorite ?? false

        item.userData?.isFavorite = !beforeIsFavorite
        do {
            try await setIsFavorite(!beforeIsFavorite)
        } catch {
            item.userData?.isFavorite = beforeIsFavorite
        }
    }

    @MainActor
    private func setIsPlayed(_ isPlayed: Bool) async throws {
        guard let itemID = item.id,
              let userSession = Container.shared.currentUserSession()
        else { return }

        let request: Request<UserItemDataDto> = if isPlayed {
            Paths.markPlayedItem(
                itemID: itemID,
                userID: userSession.user.id
            )
        } else {
            Paths.markUnplayedItem(
                itemID: itemID,
                userID: userSession.user.id
            )
        }

        let response = try await userSession.client.send(request)
        item.userData = response.value
        Notifications[.itemUserDataDidChange].post(response.value)
        Notifications[.itemShouldRefreshMetadata].post(itemID)

        if userSession.couch.isGroup {
            // Waits for every member, then toasts who was updated.
            await CouchPlayedFeedback.mirror(itemID: itemID, isPlayed: isPlayed, in: userSession)
        } else {
            userSession.couchPlaybackService.mirrorPlayed(itemID: itemID, isPlayed: isPlayed)
        }
    }

    private func setIsFavorite(_ isFavorite: Bool) async throws {
        guard let itemID = item.id,
              let userSession = Container.shared.currentUserSession()
        else { return }

        let request: Request<UserItemDataDto> = if isFavorite {
            Paths.markFavoriteItem(
                itemID: itemID,
                userID: userSession.user.id
            )
        } else {
            Paths.unmarkFavoriteItem(
                itemID: itemID,
                userID: userSession.user.id
            )
        }

        let response = try await userSession.client.send(request)
        item.userData = response.value
        Notifications[.itemUserDataDidChange].post(response.value)
        Notifications[.itemShouldRefreshMetadata].post(itemID)
    }
}
