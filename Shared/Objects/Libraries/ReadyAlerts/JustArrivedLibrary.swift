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
/// instead of blanking the home. A restricted member (a kid) that couldn't be checked fails closed
/// (`CouchItemFilter.filter(_:members:memberResults:primaryID:excludePlayedBy:)`).
struct JustArrivedLibrary: BaseItemKindLibrary {

    /// The home shows nothing until every row loaded, so a slow refresh (an unreachable Seerr
    /// times out after 20 s per person) isn't awaited longer than this. It keeps running,
    /// and the row uses the arrivals the service already had.
    private static let refreshWaitLimit: Duration = .seconds(4)

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
            let refresh = Task {
                await service.refresh(session: session)
            }

            await Self.wait(for: refresh, atMost: Self.refreshWaitLimit)
        }

        var seenItemIDs: Set<String> = []
        var items: [BaseItemDto] = []
        // Series that were already in the library when wished for: a new season arrived
        var newMediaSeriesIDs: Set<String> = []

        for arrival in service.arrivals(forMembers: couch.memberIDs) {
            guard let item = service.item(for: arrival),
                  let itemID = item.id,
                  seenItemIDs.insert(itemID).inserted
            else { continue }

            if item.type == .series, let dateCreated = item.dateCreated, dateCreated <= arrival.wishedAt {
                newMediaSeriesIDs.insert(itemID)
            }

            items.append(item)
        }

        guard items.isNotEmpty else { return [] }

        // The primary user's own history counts too. This also drops what someone
        // on the couch can't access (library access, parental controls).
        let check = await CouchItemFilter.memberResults(
            ids: CouchItemFilter.uniqueIDs(of: items),
            couch: couch,
            primary: session,
            // Jellyfin 10.10 only fills a series' `playedPercentage` with this field
            fields: [.recursiveItemCount],
            enableImages: false
        )

        let memberResults = check.results.map { memberItems in
            memberItems?.map { Self.ignoringEarlierSeasons($0, newMediaSeriesIDs: newMediaSeriesIDs) }
        }

        // Fails closed: when a restricted member (a kid) couldn't be checked,
        // only what an at least as restricted member verified is kept.
        let unplayedItems = CouchItemFilter.filter(
            items,
            members: check.members,
            memberResults: memberResults,
            // The arrivals come from the service's cache, not from the primary user's own request
            primaryID: nil,
            excludePlayedBy: .allMembers
        )

        return CouchHomeSupport.page(unplayedItems, pageState)
    }

    /// A new season of a series someone already started: the earlier seasons don't make it watched,
    /// only a series played to the end does.
    private static func ignoringEarlierSeasons(
        _ item: BaseItemDto,
        newMediaSeriesIDs: Set<String>
    ) -> BaseItemDto {
        guard let id = item.id,
              newMediaSeriesIDs.contains(id),
              item.userData?.isPlayed != true
        else { return item }

        var item = item
        item.userData = nil
        return item
    }

    /// Waits until `task` finished or `limit` passed, whichever comes first. `task` keeps running.
    private static func wait(for task: Task<Void, Never>, atMost limit: Duration) async {
        let resumeState = JustArrivedResumeState()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let timer = Task {
                try? await Task.sleep(for: limit)

                if resumeState.resume() {
                    continuation.resume()
                }
            }

            Task {
                await task.value
                timer.cancel()

                if resumeState.resume() {
                    continuation.resume()
                }
            }
        }
    }
}

/// Lets only the first of several callers resume a continuation.
private final class JustArrivedResumeState: @unchecked Sendable {

    private let lock = NSLock()
    private var didResume = false

    func resume() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard !didResume else { return false }

        didResume = true
        return true
    }
}
