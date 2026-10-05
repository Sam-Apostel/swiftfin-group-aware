//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

/// "Latest Movies" on a group's home: the primary user's latest items in a library (`LatestInLibrary`),
/// checked with every couch member's own account.
///
/// - Only items every member can access are kept, failing closed when a restricted member
///   (a kid) couldn't be checked.
/// - An item is hidden once everyone on the couch watched it (a series: every episode played).
/// - Toddler content is dropped when a child and adults watch together.
struct CouchLatestInLibrary: BaseItemKindLibrary {

    let couch: CouchGroup
    let latest: LatestInLibrary

    var libraryItemTypes: [BaseItemKind] {
        latest.libraryItemTypes
    }

    var parent: TitledLibraryParent {
        latest.parent
    }

    init(library: BaseItemDto, couch: CouchGroup) {
        self.couch = couch
        self.latest = LatestInLibrary(library: library)
    }

    func retrievePage(
        environment: Empty,
        pageState: LibraryPageState
    ) async throws -> [BaseItemDto] {
        let primary = pageState.userSession

        let latestItems = try await latest.retrievePage(
            environment: environment,
            pageState: LibraryPageState(
                pageOffset: 0,
                pageSize: Self.windowSize(for: pageState),
                userSession: primary
            )
        )

        guard latestItems.isNotEmpty else { return [] }

        let check = await CouchItemFilter.memberResults(
            ids: CouchItemFilter.uniqueIDs(of: latestItems),
            couch: couch,
            primary: primary,
            // Jellyfin 10.10 only fills a series' `playedPercentage` with this field.
            fields: [.recursiveItemCount],
            enableImages: false
        )

        let memberResults = check.results.map { memberItems in
            memberItems?.map { Self.ignoringPartlyWatchedFolders($0) }
        }

        // Fails closed: when a restricted member (a kid) couldn't be checked,
        // only what an at least as restricted member verified is kept.
        let accessibleItems = CouchItemFilter.filter(
            latestItems,
            members: check.members,
            memberResults: memberResults,
            primaryID: primary.user.id,
            excludePlayedBy: .allMembers
        )

        let items = await CouchHomeSupport.removingToddlerContent(
            accessibleItems,
            couch: couch,
            session: primary
        )

        return CouchHomeSupport.page(items, pageState)
    }

    /// Latest groups new episodes into their series (or season), which is in the row because something new
    /// arrived: it only counts as watched once every episode is played, not as soon as some were.
    private static func ignoringPartlyWatchedFolders(_ item: BaseItemDto) -> BaseItemDto {
        let isFolderLike = item.isFolder == true || item.type == .series || item.type == .season

        guard isFolderLike, item.userData?.isPlayed != true else { return item }

        var item = item
        item.userData = nil
        return item
    }

    /// How many latest items are filtered to fill the requested page.
    ///
    /// Filtering is per item, so a larger window keeps the earlier pages identical.
    private static func windowSize(for pageState: LibraryPageState) -> Int {
        let requested = (pageState.pageOffset + pageState.pageSize) * 2

        return min(200, max(40, requested))
    }
}
