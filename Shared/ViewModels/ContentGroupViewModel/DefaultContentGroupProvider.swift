//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import FactoryKit
import Foundation
import JellyfinAPI

struct DefaultContentGroupProvider: ContentGroupProvider {

    @Injected(\.currentUserSession)
    var userSession: UserSession?

    let id: String = "default-content-group-provider"

    /// "Home", or who's on the couch when a group is watching together ("Sam & Lisa", "Together").
    var displayTitle: String {
        if let couch = groupCouch {
            return L10n.Couch.homeTitle(couch: couch)
        }

        return L10n.home
    }

    /// A group's home has a "Picked for…" row that follows the watchlist live.
    var picksCouch: CouchGroup? {
        groupCouch
    }

    /// The current couch, when more than one person is on it.
    private var groupCouch: CouchGroup? {
        guard let couch = userSession?.couch, couch.isGroup else { return nil }

        return couch
    }

    func makeGroups(environment: Empty) async throws -> [any ContentGroup] {
        guard let userSession else { return [] }

        let parameters = Paths.GetUserViewsParameters(userID: userSession.user.id)
        let userViewsPath = Paths.getUserViews(parameters: parameters)
        let userViews = try await userSession.client.send(userViewsPath)
        let excludedLibraryIDs = userSession.user.data.configuration?.latestItemsExcludes ?? []

        let resolvedUserViews = (userViews.value.items ?? [])
            .subtracting(excludedLibraryIDs, using: \.id)
            .intersecting(
                [
                    .homevideos,
                    .movies,
                    .musicvideos,
                    .tvshows,
                ],
                using: \.collectionType
            )

        if let couch = groupCouch {
            return _makeCouchGroups(userViews: resolvedUserViews, couch: couch)
        }

        return _makeGroups(userViews: resolvedUserViews)
    }

    @ContentGroupBuilder
    private func _makeGroups(userViews: [BaseItemDto]) -> [any ContentGroup] {

        #if os(tvOS)
        let cinematicSelectionContentGroup = CinematicSelectionContentGroup(
            resumeLibrary: ResumeItemsLibrary(mediaTypes: [.video]),
            recentlyAddedLibrary: RecentlyAddedLibrary()
        )

        cinematicSelectionContentGroup
        #else
        PosterGroup(
            library: ResumeItemsLibrary(mediaTypes: [.video]),
            posterDisplayType: .landscape,
            posterSize: .medium,
            _viewContext: .isInResume
        )
        #endif

        if Defaults[.ReadyAlerts.showJustArrivedRow], let couch = userSession?.couch {
            PosterGroup(id: "ready-just-arrived", library: JustArrivedLibrary(couch: couch), posterDisplayType: .portrait)
        }

        PosterGroup(
            library: NextUpLibrary()
        )

        if Defaults[.Customization.Home.showRecentlyAdded] {
            #if os(tvOS)
            CinematicRecentlyAddedContentGroup(
                viewModel: cinematicSelectionContentGroup.viewModel
            )
            #else
            PosterGroup(
                library: ItemLibrary(
                    parent: BaseItemDto(name: L10n.recentlyAdded.localizedCapitalized),
                    filters: .init(
                        itemTypes: [.movie, .series],
                        sortBy: [.dateCreated],
                        sortOrder: [.descending]
                    )
                )
            )
            #endif
        }

        _makeTrailingGroups(userViews: userViews)
    }

    /// The home of a group on the couch: the couch rows first, then the regular rows of the primary user.
    ///
    /// Every couch row fetches each member's data with that member's own session,
    /// and a member that fails is skipped, so these rows never fail the whole home.
    @ContentGroupBuilder
    private func _makeCouchGroups(userViews: [BaseItemDto], couch: CouchGroup) -> [any ContentGroup] {

        #if os(tvOS)
        // The cinematic hero shows what the couch is watching together,
        // or what's new for all of them when nothing is in progress.
        let cinematicSelectionContentGroup = CinematicSelectionContentGroup(
            resumeLibrary: ResumeItemsLibrary(mediaTypes: [.video], couch: couch),
            recentlyAddedLibrary: RecentlyAddedLibrary(couch: couch)
        )

        cinematicSelectionContentGroup
        #endif

        PosterGroup(
            id: "couch-picked",
            library: CouchPickedLibrary(couch: couch),
            posterDisplayType: .portrait
        )

        if Defaults[.ReadyAlerts.showJustArrivedRow] {
            PosterGroup(id: "ready-just-arrived", library: JustArrivedLibrary(couch: couch), posterDisplayType: .portrait)
        }

        #if !os(tvOS)
        PosterGroup(
            id: "couch-resume",
            library: CouchResumeLibrary(couch: couch),
            posterDisplayType: .landscape,
            posterSize: .medium,
            _viewContext: .isInResume
        )
        #endif

        // `.isInResume`: an episode one member already watched is still next up for the others,
        // so don't mark it as played.
        PosterGroup(
            id: "couch-nextup",
            library: CouchNextUpLibrary(couch: couch),
            posterDisplayType: .landscape,
            _viewContext: .isInResume
        )

        #if os(tvOS)
        CinematicRecentlyAddedContentGroup(
            viewModel: cinematicSelectionContentGroup.viewModel
        )
        #else
        PosterGroup(
            id: "couch-new",
            library: CouchNewForEveryoneLibrary(couch: couch),
            posterDisplayType: .portrait
        )
        #endif

        // The regular rows, as the primary user

        PosterGroup(
            library: ResumeItemsLibrary(mediaTypes: [.video]),
            posterDisplayType: .landscape,
            posterSize: .medium,
            _viewContext: .isInResume
        )

        PosterGroup(
            library: NextUpLibrary()
        )

        if Defaults[.Customization.Home.showRecentlyAdded] {
            #if os(tvOS)
            PosterGroup(
                library: RecentlyAddedLibrary()
            )
            #else
            PosterGroup(
                library: ItemLibrary(
                    parent: BaseItemDto(name: L10n.recentlyAdded.localizedCapitalized),
                    filters: .init(
                        itemTypes: [.movie, .series],
                        sortBy: [.dateCreated],
                        sortOrder: [.descending]
                    )
                )
            )
            #endif
        }

        _makeTrailingGroups(userViews: userViews)
    }

    /// The rows after "Recently Added", the same for a single user and a group.
    @ContentGroupBuilder
    private func _makeTrailingGroups(userViews: [BaseItemDto]) -> [any ContentGroup] {

        if Defaults[.Customization.Home.showRecentlyPlayed] {
            PosterGroup(
                library: ItemLibrary(
                    parent: BaseItemDto(name: L10n.recentlyPlayed.localizedCapitalized),
                    filters: .init(
                        itemTypes: [.movie, .series],
                        sortBy: [.datePlayed],
                        sortOrder: [.descending],
                        traits: [.isPlayed]
                    )
                )
            )
        }

        PosterGroup(
            id: "programs-recommended",
            library: RecommendedProgramsLibrary(),
            posterDisplayType: .landscape,
            posterSize: .small
        )

        userViews
            .map(LatestInLibrary.init)
            .map {
                PosterGroup(
                    library: $0,
                    posterDisplayType: .landscape
                )
            }
    }
}
