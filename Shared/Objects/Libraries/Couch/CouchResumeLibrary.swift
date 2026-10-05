//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

/// "Continue Watching Together": the primary user's resume items
/// that every other couch member is in the middle of too.
///
/// Members are checked with their own session. A member whose request fails is skipped;
/// when no other member can be checked, the row is empty.
struct CouchResumeLibrary: BaseItemKindLibrary {

    let couch: CouchGroup
    let libraryItemTypes: [BaseItemKind] = [.episode, .movie, .video]
    let parent: TitledLibraryParent = .init(
        displayTitle: L10n.CouchHome.continueWatchingTogether,
        id: "couch-resume"
    )

    func retrievePage(
        environment: Empty,
        pageState: LibraryPageState
    ) async throws -> [BaseItemDto] {
        let primary = pageState.userSession
        let members = CouchHomeSupport.memberSessions(for: couch, primary: primary)

        guard members.isNotEmpty else { return [] }

        let primaryItems = try await ResumeItemsLibrary(mediaTypes: [.video]).retrievePage(
            environment: .default,
            pageState: LibraryPageState(
                pageOffset: 0,
                pageSize: CouchHomeSupport.memberWindowSize,
                userSession: primary
            )
        )

        let ids = CouchItemFilter.uniqueIDs(of: primaryItems)

        guard ids.isNotEmpty else { return [] }

        let memberResults = await CouchItemFilter.fetchItems(
            ids: ids,
            seenBy: members,
            fields: nil,
            enableImages: false
        )

        let items = await CouchHomeSupport.removingToddlerContent(
            Self.togetherItems(primaryItems, memberResults: memberResults),
            couch: couch,
            session: primary
        )

        return CouchHomeSupport.page(items, pageState)
    }

    /// The primary user's resume items that every checked member has a resume position in.
    ///
    /// - Parameter memberResults: Per other member, the primary user's resume items as that member
    ///   sees them, or `nil` when that member couldn't be checked.
    /// - Returns: `[]` when no member could be checked: nothing is known to be "together".
    static func togetherItems(
        _ primaryItems: [BaseItemDto],
        memberResults: [[BaseItemDto]?]
    ) -> [BaseItemDto] {
        var togetherIDs = Set(CouchItemFilter.uniqueIDs(of: primaryItems))
        var checkedMembers = 0

        for memberItems in memberResults {
            guard let memberItems else { continue }

            checkedMembers += 1

            let inProgressIDs = memberItems
                .filter { isInProgress($0) }
                .compactMap(\.id)

            togetherIDs.formIntersection(inProgressIDs)
        }

        guard checkedMembers > 0 else { return [] }

        return primaryItems.filter { item in
            guard let id = item.id else { return false }

            return togetherIDs.contains(id)
        }
    }

    func onItemUserDataChanged(
        viewModel: PagingLibraryViewModel<CouchResumeLibrary>,
        userData: UserItemDataDto
    ) {
        guard let itemID = userData.itemID else { return }

        if userData.isPlayed == true {
            viewModel.elements.removeAll { $0.id == itemID }
            return
        }

        let isAlreadyLoaded = viewModel.elements.contains { $0.id == itemID }
        guard !isAlreadyLoaded else { return }
        guard (userData.playbackPositionTicks ?? 0) > 0 else { return }

        viewModel.scheduleRefreshForItemUserData(minimumInterval: 30)
    }

    /// Whether the member has a resume position in the item.
    private static func isInProgress(_ item: BaseItemDto) -> Bool {
        guard let userData = item.userData else { return false }

        return userData.isPlayed != true && (userData.playbackPositionTicks ?? 0) > 0
    }
}
