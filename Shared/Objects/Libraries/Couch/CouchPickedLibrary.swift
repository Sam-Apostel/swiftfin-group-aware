//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

/// "Picked for Sam and Lisa": the household watchlist entries (`AudienceWatchlistStore`)
/// whose audience is **exactly** the people on the couch, resolved to library items.
///
/// Picks for only some of the people on the couch (a show picked for the kid alone)
/// don't show up while others are on the couch too.
struct CouchPickedLibrary: BaseItemKindLibrary {

    let couch: CouchGroup
    let libraryItemTypes: [BaseItemKind] = [.movie, .series]
    let parent: TitledLibraryParent

    init(couch: CouchGroup) {
        self.couch = couch
        self.parent = .init(
            displayTitle: L10n.CouchHome.pickedFor(couch.displayNames),
            id: "couch-picked"
        )
    }

    func retrievePage(
        environment: Empty,
        pageState: LibraryPageState
    ) async throws -> [BaseItemDto] {
        let items = await CouchHomeSupport.pickedItems(
            couch: couch,
            session: pageState.userSession,
            refreshStore: pageState.pageOffset == 0
        )

        return CouchHomeSupport.page(items, pageState)
    }
}
