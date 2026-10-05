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

    /// Whether the item's user data says it was played or started.
    ///
    /// A series is only marked played once every episode is played, so a partly watched
    /// series is recognized by its `playedPercentage` (only filled for folders and started videos).
    static func hasWatched(_ item: BaseItemDto) -> Bool {
        guard let userData = item.userData else { return false }

        return userData.isPlayed == true
            || (userData.playbackPositionTicks ?? 0) > 0
            || (userData.playedPercentage ?? 0) > 0
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
