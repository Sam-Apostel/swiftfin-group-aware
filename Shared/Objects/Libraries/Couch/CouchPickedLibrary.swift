//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

/// The household watchlist entries (`AudienceWatchlistStore`) for this couch, resolved to library items:
/// the same picks the decider uses (`CouchHomeSupport.pickEntries(for:)`).
///
/// - A group, "Picked for Sam and Lisa": the picks whose audience is **exactly** the people on the couch.
///   Picks for only some of them (a show picked for the kid alone) don't show up while others are on the couch too.
/// - Alone, "Picked for you": every pick that includes this person ("Just Sam", "Sam & Lisa", …).
///
/// Like the group row, picks are exempt from the "watched" filter: the ones everyone already played come last.
struct CouchPickedLibrary: BaseItemKindLibrary {

    let couch: CouchGroup
    let libraryItemTypes: [BaseItemKind] = [.movie, .series]
    let parent: TitledLibraryParent

    init(couch: CouchGroup) {
        self.couch = couch
        self.parent = .init(
            displayTitle: couch.isGroup
                ? L10n.CouchHome.pickedFor(couch.displayNames)
                : L10n.CouchDecider.pickedForYou,
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
