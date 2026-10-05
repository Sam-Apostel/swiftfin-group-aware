//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import Foundation
import JellyfinAPI

/// "Just arrived": tagged or requested titles that recently landed in the library,
/// for the user alone or for everyone on the couch (`ReadyAlertRules.isVisible`), newest arrival first.
///
/// The arrivals come from `ReadyAlertsService`. A title drops out once it was played by the solo user,
/// or by every person on the couch, and the service ages it out after 14 days.
///
/// Never throws: a failing service or member fetch yields fewer (or no) items, so the row is hidden
/// instead of blanking the home.
struct JustArrivedLibrary: BaseItemKindLibrary {

    let couch: CouchGroup
    let libraryItemTypes: [BaseItemKind] = [.movie, .series]
    let parent: TitledLibraryParent

    init(couch: CouchGroup) {
        self.couch = couch
        self.parent = .init(
            displayTitle: L10n.ReadyAlerts.justArrived,
            id: "ready-just-arrived"
        )
    }

    func retrievePage(
        environment: Empty,
        pageState: LibraryPageState
    ) async throws -> [BaseItemDto] {
        let session = pageState.userSession
        let service = Container.shared.readyAlertsService()

        // The service throttles itself, so a home refresh doesn't hit the server every time.
        if pageState.pageOffset == 0 {
            await service.refresh(session: session)
        }

        var seenItemIDs: Set<String> = []
        var items: [BaseItemDto] = []

        for arrival in service.arrivals(forMembers: couch.memberIDs) {
            guard let item = service.item(for: arrival),
                  let itemID = item.id,
                  seenItemIDs.insert(itemID).inserted
            else { continue }

            items.append(item)
        }

        guard items.isNotEmpty else { return [] }

        // The primary user's own history counts too. This also drops what someone
        // on the couch can't access (library access, parental controls).
        let sessions = [session] + CouchHomeSupport.memberSessions(for: couch, primary: session)

        let unplayedItems = await CouchItemFilter.filter(
            items,
            memberSessions: sessions,
            excludePlayedBy: .allMembers
        )

        return CouchHomeSupport.page(unplayedItems, pageState)
    }
}
