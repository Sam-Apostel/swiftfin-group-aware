//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

/// Whose watch history hides an item from a couch row.
enum CouchPlayedRule {

    /// Hide an item as soon as one member has watched it.
    case anyMember

    /// Hide an item only when every member has watched it.
    case allMembers
}

/// Filters items with the access and watch history of several couch members.
///
/// Every member is queried with their own session (one `/Items?ids=` request per member,
/// in chunks), so their library access and server-side parental controls apply.
@MainActor
enum CouchItemFilter {

    /// The most item ids sent in one `/Items?ids=` request.
    ///
    /// Keeps the request line well under the server's 8 KB limit.
    static let maxIDsPerRequest = 80

    /// Keeps the items that every member can access and that weren't watched, following `excludePlayedBy`.
    ///
    /// An item counts as watched by a member when it is marked played for them,
    /// when they have a resume position in it, or (a series) when they played some of its episodes.
    ///
    /// - Parameters:
    ///   - items: The items to filter. Their order is kept.
    ///   - memberSessions: The session of every member to check. Include the primary user's session
    ///     when their own watch history should count too.
    ///   - excludePlayedBy: Whose watch history hides an item.
    /// - Returns: The filtered items. A member whose request fails is skipped (and logged), so this never throws.
    ///   When no member could be checked, `items` is returned unchanged.
    static func filter(
        _ items: [BaseItemDto],
        memberSessions: [UserSession],
        excludePlayedBy: CouchPlayedRule
    ) async -> [BaseItemDto] {
        let ids = uniqueIDs(of: items)

        guard ids.isNotEmpty, memberSessions.isNotEmpty else { return items }

        let memberResults = await fetchItems(
            ids: ids,
            seenBy: memberSessions,
            // Jellyfin 10.10 only fills a series' `playedPercentage` with this field.
            fields: [.recursiveItemCount],
            enableImages: false
        )

        return filter(
            items,
            memberResults: memberResults,
            excludePlayedBy: excludePlayedBy
        )
    }

    /// The filtering itself, without requests.
    ///
    /// - Parameter memberResults: Per member, the items as that member sees them,
    ///   or `nil` when that member couldn't be checked.
    static func filter(
        _ items: [BaseItemDto],
        memberResults: [[BaseItemDto]?],
        excludePlayedBy: CouchPlayedRule
    ) -> [BaseItemDto] {
        var visibleToEveryone = Set(uniqueIDs(of: items))
        var watchedCounts: [String: Int] = [:]
        var checkedMembers = 0

        for memberItems in memberResults {
            guard let memberItems else { continue }

            checkedMembers += 1
            visibleToEveryone.formIntersection(memberItems.compactMap(\.id))

            for memberItem in memberItems where hasWatched(memberItem) {
                guard let id = memberItem.id else { continue }

                watchedCounts[id, default: 0] += 1
            }
        }

        guard checkedMembers > 0 else { return items }

        return items.filter { item in
            guard let id = item.id, visibleToEveryone.contains(id) else { return false }

            let watchedCount = watchedCounts[id] ?? 0

            switch excludePlayedBy {
            case .anyMember:
                return watchedCount == 0
            case .allMembers:
                return watchedCount < checkedMembers
            }
        }
    }

    // MARK: - Fail closed for restricted members

    /// Keeps the items that every couch member can access and that weren't watched, following
    /// `excludePlayedBy`, checked with every member's own account.
    ///
    /// Unlike `filter(_:memberSessions:excludePlayedBy:)`, this fails closed for restricted members
    /// (kids, server age limits): see `filter(_:members:memberResults:primaryID:excludePlayedBy:)`.
    /// A member without a stored sign-in counts as a member that couldn't be checked.
    static func filter(
        _ items: [BaseItemDto],
        couch: CouchGroup,
        primary: UserSession,
        excludePlayedBy: CouchPlayedRule
    ) async -> [BaseItemDto] {
        let ids = uniqueIDs(of: items)

        guard ids.isNotEmpty else { return items }

        let check = await memberResults(
            ids: ids,
            couch: couch,
            primary: primary,
            // Jellyfin 10.10 only fills a series' `playedPercentage` with this field.
            fields: [.recursiveItemCount],
            enableImages: false
        )

        return filter(
            items,
            members: check.members,
            memberResults: check.results,
            primaryID: primary.user.id,
            excludePlayedBy: excludePlayedBy
        )
    }

    /// Fetches the items with these ids as seen by every couch member (the primary user first), concurrently.
    ///
    /// - Returns: The members in couch order and one result per member. The result is `nil` for a member
    ///   whose request failed, or who has no stored sign-in (recorded in `CouchMemberHealth`).
    static func memberResults(
        ids: [String],
        couch: CouchGroup,
        primary: UserSession,
        fields: [ItemFields]? = PosterSubtitleField.itemFields,
        enableImages: Bool = true
    ) async -> (members: [UserState], results: [[BaseItemDto]?]) {
        var members: [UserState] = [primary.user]
        var sessions: [UserSession] = [primary]
        var sessionIndices: [Int] = [0]

        for member in couch.members where member.id != primary.user.id {
            members.append(member)

            guard let session = CouchHomeSupport.memberSession(for: member, primary: primary) else { continue }

            sessions.append(session)
            sessionIndices.append(members.count - 1)
        }

        let fetched = await fetchItems(
            ids: ids,
            seenBy: sessions,
            fields: fields,
            enableImages: enableImages
        )

        var results: [[BaseItemDto]?] = Array(repeating: nil, count: members.count)

        for (index, memberItems) in zip(sessionIndices, fetched) {
            results[index] = memberItems
        }

        return (members: members, results: results)
    }

    /// The filtering itself, without requests, failing closed for restricted members.
    ///
    /// - Every member that could be checked must be able to access an item, and their watch history
    ///   counts for `excludePlayedBy`, as in `filter(_:memberResults:excludePlayedBy:)`.
    /// - When a restricted member other than the primary user couldn't be checked (`nil` result),
    ///   only items verified by a checked restricted member who is at least as restricted
    ///   (`UserState.restrictionScore`) are kept. When there is no such member, this returns `[]`:
    ///   a row never shows what a child on the couch might not be allowed to see.
    ///
    /// - Parameters:
    ///   - members: The couch members, in the same order as `memberResults`.
    ///   - memberResults: Per member, the items as that member sees them, or `nil` when that member couldn't be checked.
    ///   - primaryID: The id of the primary user, when `items` come from their own request, so their access
    ///     is never in doubt. `nil` when the items came from elsewhere (a cache): the primary user is then
    ///     checked like everyone else.
    static func filter(
        _ items: [BaseItemDto],
        members: [UserState],
        memberResults: [[BaseItemDto]?],
        primaryID: String?,
        excludePlayedBy: CouchPlayedRule
    ) -> [BaseItemDto] {
        let isAnyoneRestricted = members.contains(where: \.isRestricted)

        // Results that can't be matched to their members can't be trusted
        guard members.count == memberResults.count else {
            return isAnyoneRestricted ? [] : filter(items, memberResults: memberResults, excludePlayedBy: excludePlayedBy)
        }

        let checks = Array(zip(members, memberResults))

        // The strictest restricted member that couldn't be checked
        let uncheckedRestrictionScore = checks
            .filter { check in
                check.1 == nil && check.0.isRestricted && check.0.id != primaryID
            }
            .map { check in check.0.restrictionScore }
            .min()

        let filtered = filter(items, memberResults: memberResults, excludePlayedBy: excludePlayedBy)

        guard let uncheckedRestrictionScore else { return filtered }

        // Someone checked must stand in for them: restricted at least as much
        let hasStandIn = checks.contains { check in
            check.1 != nil && check.0.isRestricted && check.0.restrictionScore <= uncheckedRestrictionScore
        }

        guard hasStandIn else { return [] }

        // `filtered` only keeps items every checked member can access, the stand-in included
        return filtered
    }

    /// Whether the item's user data says the member watched it.
    ///
    /// - A movie, video or episode counts once it is marked played or at least half watched,
    ///   so a film someone tried for 15 minutes still shows up for the couch.
    /// - A series (or another folder) is only marked played once every episode is played,
    ///   so a partly watched series is recognized by its `playedPercentage`
    ///   (only filled for folders and started videos).
    static func hasWatched(_ item: BaseItemDto) -> Bool {
        guard let userData = item.userData else { return false }

        if userData.isPlayed == true {
            return true
        }

        let playedPercentage = userData.playedPercentage ?? 0

        if isFolderLike(item) {
            return playedPercentage > 0
        }

        return playedPercentage >= watchedPercentage
    }

    /// From how far into a movie or video it counts as watched.
    static let watchedPercentage: Double = 50

    /// A series, season or other folder: its played state is the sum of its children.
    private static func isFolderLike(_ item: BaseItemDto) -> Bool {
        if item.isFolder == true {
            return true
        }

        switch item.type {
        case .series, .season, .boxSet, .folder, .collectionFolder:
            return true
        default:
            return false
        }
    }

    /// Fetches the items with these ids as seen by `session`, in chunks.
    ///
    /// Items the user can't access (library access, parental controls) are missing from the result,
    /// and the user data is the user's own.
    ///
    /// - Important: Returns `[]` without a request for empty `ids`: `/Items` without ids would return the root folders.
    static func fetchItems(
        ids: [String],
        session: UserSession,
        fields: [ItemFields]? = PosterSubtitleField.itemFields,
        enableImages: Bool = true
    ) async throws -> [BaseItemDto] {
        guard ids.isNotEmpty else { return [] }

        var result: [BaseItemDto] = []
        var start = 0

        while start < ids.count {
            let end = min(start + maxIDsPerRequest, ids.count)
            let chunk = Array(ids[start ..< end])
            start = end

            var parameters = Paths.GetItemsParameters()
            parameters.enableImages = enableImages
            parameters.enableUserData = true
            parameters.fields = fields
            parameters.ids = chunk
            parameters.limit = chunk.count
            parameters.userID = session.user.id

            let request = Paths.getItems(parameters: parameters)
            let response = try await session.client.send(request)

            result.append(contentsOf: response.value.items ?? [])
        }

        return result
    }

    /// Fetches the items with these ids as seen by every session, concurrently.
    ///
    /// - Returns: One result per session, in the order of `sessions`.
    ///   The result is `nil` for a session whose request failed; the error is logged.
    static func fetchItems(
        ids: [String],
        seenBy sessions: [UserSession],
        fields: [ItemFields]? = PosterSubtitleField.itemFields,
        enableImages: Bool = true
    ) async -> [[BaseItemDto]?] {
        await CouchHomeSupport.perSession(sessions) { session in
            try await CouchItemFilter.fetchItems(
                ids: ids,
                session: session,
                fields: fields,
                enableImages: enableImages
            )
        }
    }

    /// The ids of the items, without duplicates, in order.
    static func uniqueIDs(of items: [BaseItemDto]) -> [String] {
        var seen: Set<String> = []
        var ids: [String] = []

        for item in items {
            guard let id = item.id, seen.insert(id).inserted else { continue }

            ids.append(id)
        }

        return ids
    }
}
