//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Foundation
import JellyfinAPI

/// "New for All of You": recently added movies and shows that every couch member can watch
/// and that nobody on the couch has watched yet.
///
/// With `Defaults[.Couch.hideWatchedByAnyMember]` off, an item is only hidden once
/// every member has watched it.
struct CouchNewForEveryoneLibrary: BaseItemKindLibrary {

    let couch: CouchGroup
    let libraryItemTypes: [BaseItemKind] = [.movie, .series]
    let parent: TitledLibraryParent = .init(
        displayTitle: L10n.CouchHome.newForAllOfYou,
        id: "couch-new"
    )

    func retrievePage(
        environment: Empty,
        pageState: LibraryPageState
    ) async throws -> [BaseItemDto] {
        let primary = pageState.userSession
        let playedRule: CouchPlayedRule = Defaults[.Couch.hideWatchedByAnyMember] ? .anyMember : .allMembers

        var parameters = Paths.GetItemsParameters()
        parameters.enableUserData = true
        parameters.fields = PosterSubtitleField.itemFields
        parameters.includeItemTypes = [.movie, .series]
        parameters.isRecursive = true
        parameters.limit = Self.windowSize(for: pageState)
        parameters.sortBy = [.dateCreated]
        parameters.sortOrder = [.descending]
        parameters.userID = primary.user.id

        // The primary user's own watch history is filtered by the server,
        // which leaves more room in the window for the other members.
        if playedRule == .anyMember {
            parameters.isPlayed = false
        }

        let request = Paths.getItems(parameters: parameters)
        let response = try await primary.client.send(request)
        let recentlyAdded = response.value.items ?? []

        // Fails closed: when a restricted member (a kid) couldn't be checked,
        // only what an at least as restricted member verified is kept.
        let unwatched = await CouchItemFilter.filter(
            recentlyAdded,
            couch: couch,
            primary: primary,
            excludePlayedBy: playedRule
        )

        let items = await CouchHomeSupport.removingToddlerContent(
            unwatched,
            couch: couch,
            session: primary
        )

        return CouchHomeSupport.page(items, pageState)
    }

    /// How many recently added items are filtered to fill the requested page.
    ///
    /// Filtering is per item, so a larger window keeps the earlier pages identical.
    private static func windowSize(for pageState: LibraryPageState) -> Int {
        let requested = (pageState.pageOffset + pageState.pageSize) * 2

        return min(300, max(100, requested))
    }
}
