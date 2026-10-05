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

    /// The home of a group on the couch: the couch rows first, then the primary user's own rows,
    /// named after them and only where they can't show anything a restricted member shouldn't see.
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

        CouchDeciderEntryGroup(couch: couch)

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

        // The primary user's own rows, below the couch rows.
        //
        // Recently Added and Recently Played are left out: "New for All of You" and the couch rows
        // cover them. Continue Watching and Next Up are the primary user's unfiltered lists,
        // so they are named after them, and hidden whenever anyone on the couch is restricted
        // (a kid, or a server age limit), whoever the primary user is.
        if !couch.hasRestrictedMember {
            PosterGroup(
                library: ResumeItemsLibrary(
                    mediaTypes: [.video],
                    title: L10n.CouchHome.personalRow(
                        name: couch.primary.username,
                        title: L10n.CouchHome.continueWatching
                    )
                ),
                posterDisplayType: .landscape,
                posterSize: .medium,
                _viewContext: .isInResume
            )

            PosterGroup(
                library: NextUpLibrary(
                    title: L10n.CouchHome.personalRow(
                        name: couch.primary.username,
                        title: L10n.nextUp
                    )
                )
            )
        }

        _makeTrailingGroups(userViews: userViews, couch: couch)
    }

    /// The rows after "Recently Added".
    ///
    /// - Parameter couch: A group on the couch, or `nil` on a single user's home (unchanged).
    ///   A group gets no Recently Played, Live TV recommendations only without a restricted member,
    ///   and Latest rows checked with every member's account (`CouchLatestInLibrary`).
    @ContentGroupBuilder
    private func _makeTrailingGroups(userViews: [BaseItemDto], couch: CouchGroup? = nil) -> [any ContentGroup] {

        let groupCouch: CouchGroup? = couch?.isGroup == true ? couch : nil
        let isGroup = groupCouch != nil
        let hasRestrictedMember = groupCouch?.hasRestrictedMember ?? false

        if !isGroup, Defaults[.Customization.Home.showRecentlyPlayed] {
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

        // The primary user's Live TV recommendations, which can't be checked against a member's access
        if !hasRestrictedMember {
            PosterGroup(
                id: "programs-recommended",
                library: RecommendedProgramsLibrary(),
                posterDisplayType: .landscape,
                posterSize: .small
            )
        }

        if let groupCouch {
            userViews
                .map { CouchLatestInLibrary(library: $0, couch: groupCouch) }
                .map {
                    PosterGroup(
                        library: $0,
                        posterDisplayType: .landscape
                    )
                }
        }

        if !isGroup {
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
}
