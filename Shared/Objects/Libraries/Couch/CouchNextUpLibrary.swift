//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI
import Logging

/// "Next Up Together": the shows that are in every couch member's Next Up.
///
/// Per show, this picks the **earliest** next episode of all members (lowest season,
/// then episode number) so nobody misses one, in the order of the primary user's Next Up.
///
/// Members are checked with their own session. A member whose request fails is skipped;
/// when no other member can be checked, the row is empty.
struct CouchNextUpLibrary: BaseItemKindLibrary {

    let couch: CouchGroup
    let libraryItemTypes: [BaseItemKind] = [.episode]
    let parent: TitledLibraryParent = .init(
        displayTitle: L10n.CouchHome.nextUpTogether,
        id: "couch-nextup"
    )

    func retrievePage(
        environment: Empty,
        pageState: LibraryPageState
    ) async throws -> [BaseItemDto] {
        let primary = pageState.userSession
        let members = CouchHomeSupport.memberSessions(for: couch, primary: primary)

        guard members.isNotEmpty else { return [] }

        let primaryEpisodes = try await Self.nextUp(for: primary)

        guard primaryEpisodes.isNotEmpty else { return [] }

        let memberResults = await CouchHomeSupport.perSession(members) { member in
            try await Self.nextUp(for: member)
        }
        let memberLists = memberResults.compactMap(\.self)

        guard memberLists.isNotEmpty else { return [] }

        let episodes = await Self.withPrimaryUserData(
            Self.togetherEpisodes(primaryEpisodes, memberLists: memberLists),
            primaryEpisodeIDs: Set(primaryEpisodes.compactMap(\.id)),
            primary: primary
        )

        let items = await CouchHomeSupport.removingToddlerContent(
            episodes,
            couch: couch,
            session: primary
        )

        return CouchHomeSupport.page(items, pageState)
    }

    /// One episode per show that is in the primary user's Next Up **and** every member's:
    /// the earliest of their next episodes, in the order of the primary user's Next Up.
    ///
    /// - Parameter memberLists: The Next Up of every other member that could be checked.
    static func togetherEpisodes(
        _ primaryEpisodes: [BaseItemDto],
        memberLists: [[BaseItemDto]]
    ) -> [BaseItemDto] {
        var togetherSeriesIDs = Set(primaryEpisodes.compactMap(\.seriesID))

        for memberEpisodes in memberLists {
            togetherSeriesIDs.formIntersection(memberEpisodes.compactMap(\.seriesID))
        }

        // The primary user's list comes first, so their copy of an episode wins a tie.
        let allLists = [primaryEpisodes] + memberLists

        var episodes: [BaseItemDto] = []
        var addedSeriesIDs: Set<String> = []

        for episode in primaryEpisodes {
            guard let seriesID = episode.seriesID,
                  togetherSeriesIDs.contains(seriesID),
                  addedSeriesIDs.insert(seriesID).inserted
            else { continue }

            let candidates = allLists.flatMap { list in
                list.filter { $0.seriesID == seriesID }
            }

            let earliest = candidates.min { isEarlier($0, than: $1) } ?? episode

            episodes.append(earliest)
        }

        return episodes
    }

    func onItemUserDataChanged(
        viewModel: PagingLibraryViewModel<CouchNextUpLibrary>,
        userData: UserItemDataDto
    ) {
        guard let itemID = userData.itemID else { return }

        if viewModel.elements.contains(where: { $0.id == itemID }) {
            viewModel.scheduleRefreshForItemUserData(minimumInterval: 3)
            return
        }

        let hasResumePosition = (userData.playbackPositionTicks ?? 0) > 0
        let canAffectMembership = hasResumePosition || userData.isPlayed != nil

        guard canAffectMembership else { return }

        viewModel.scheduleRefreshForItemUserData(minimumInterval: 30)
    }

    // MARK: - Helpers

    /// The user's own Next Up, with the user's home settings (rewatching, days in Next Up).
    private static func nextUp(for session: UserSession) async throws -> [BaseItemDto] {
        try await NextUpLibrary().retrievePage(
            environment: .default,
            pageState: LibraryPageState(
                pageOffset: 0,
                pageSize: CouchHomeSupport.memberWindowSize,
                userSession: session
            )
        )
    }

    /// Whether `lhs` comes before `rhs` in its show: lower season, then lower episode number.
    private static func isEarlier(_ lhs: BaseItemDto, than rhs: BaseItemDto) -> Bool {
        let lhsSeason = lhs.parentIndexNumber ?? Int.max
        let rhsSeason = rhs.parentIndexNumber ?? Int.max

        if lhsSeason != rhsSeason {
            return lhsSeason < rhsSeason
        }

        return (lhs.indexNumber ?? Int.max) < (rhs.indexNumber ?? Int.max)
    }

    /// Episodes taken from another member's Next Up carry that member's user data.
    /// Fetch them again as the primary user, like every other row on the home screen.
    ///
    /// If that request fails, the episodes are kept as they are.
    private static func withPrimaryUserData(
        _ episodes: [BaseItemDto],
        primaryEpisodeIDs: Set<String>,
        primary: UserSession
    ) async -> [BaseItemDto] {
        let otherIDs = episodes
            .compactMap(\.id)
            .filter { !primaryEpisodeIDs.contains($0) }

        guard otherIDs.isNotEmpty else { return episodes }

        do {
            let refetched = try await CouchItemFilter.fetchItems(ids: otherIDs, session: primary)
            let refetchedByID = CouchHomeSupport.itemsKeyedByID(refetched)

            return episodes.compactMap { episode -> BaseItemDto? in
                guard let id = episode.id, !primaryEpisodeIDs.contains(id) else { return episode }

                return refetchedByID[id]
            }
        } catch {
            Logger.swiftfin().error("Couch: could not fetch next up episodes: \(error.localizedDescription)")

            return episodes
        }
    }
}
