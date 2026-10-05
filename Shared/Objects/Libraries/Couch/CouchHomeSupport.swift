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
import Logging

/// Helpers shared by the couch home rows.
///
/// Every request made for a couch member other than the primary user is allowed to fail:
/// that member is skipped and the failure is recorded in `CouchMemberHealth`,
/// so a row never fails because of one member.
@MainActor
enum CouchHomeSupport {

    /// How many items of each member's own list (resume, next up) are compared.
    static let memberWindowSize = 50

    /// How long the watchlist store is considered fresh for the "Picked for" row.
    private static let storeRefreshInterval: TimeInterval = 30

    private static let logger = Logger.swiftfin()

    /// Lowercased genre keywords of toddler content, matched as substrings.
    ///
    /// Covers "Kids" / "Children" and the Dutch, German and French variants of
    /// non-English metadata ("Kinderen", "Kinder", "Enfants").
    private static let toddlerGenreKeywords = ["kids", "children", "kinder", "enfant"]

    // MARK: - Members

    /// The sessions of the couch members other than the primary user.
    ///
    /// Members without a stored access token have no session and are skipped
    /// (recorded in `CouchMemberHealth` as needing to sign in again).
    static func memberSessions(
        for couch: CouchGroup,
        primary: UserSession
    ) -> [UserSession] {
        couch.otherMembers.compactMap { member in
            guard member.id != primary.user.id else { return nil }

            return memberSession(for: member, primary: primary)
        }
    }

    /// The session of one couch member, or `nil` when no sign-in is stored for them
    /// (recorded in `CouchMemberHealth` as needing to sign in again).
    static func memberSession(
        for member: UserState,
        primary: UserSession
    ) -> UserSession? {
        if let session = primary.session(forMemberID: member.id) {
            return session
        }

        Container.shared.couchMemberHealth().recordFailure(
            userID: member.id,
            kind: .unauthorized,
            reason: "no stored sign-in"
        )

        return nil
    }

    /// Runs one request per session, concurrently.
    ///
    /// - Returns: One result per session, in the order of `sessions`.
    ///   The result is `nil` for a session whose request failed. Failures and successes are recorded
    ///   in `CouchMemberHealth`, which logs each failing member once per refresh.
    static func perSession(
        _ sessions: [UserSession],
        _ request: @escaping @MainActor (UserSession) async throws -> [BaseItemDto]
    ) async -> [[BaseItemDto]?] {
        await withTaskGroup(of: (Int, [BaseItemDto]?).self) { group in
            for (index, session) in sessions.enumerated() {
                group.addTask { @MainActor in
                    let health = Container.shared.couchMemberHealth()

                    do {
                        let items = try await request(session)
                        health.recordSuccess(userID: session.user.id)
                        return (index, items)
                    } catch {
                        health.recordFailure(userID: session.user.id, error: error)
                        return (index, nil)
                    }
                }
            }

            var results: [[BaseItemDto]?] = Array(repeating: nil, count: sessions.count)

            for await result in group {
                results[result.0] = result.1
            }

            return results
        }
    }

    // MARK: - Paging

    /// The requested page of a list that was computed in full.
    static func page(
        _ items: [BaseItemDto],
        _ pageState: LibraryPageState
    ) -> [BaseItemDto] {
        Array(items.dropFirst(pageState.pageOffset).prefix(pageState.pageSize))
    }

    // MARK: - Picked for this couch

    /// The watchlist picks for this couch, the one definition used by Home and the decider.
    ///
    /// - A group: the picks tagged for exactly these people ("Picked for Sam & Lisa").
    /// - Alone: every pick that includes this person ("Just Sam", "Sam & Lisa", …).
    static func pickEntries(for couch: CouchGroup) -> [AudienceWatchlistEntry] {
        let store = Container.shared.audienceWatchlistStore()

        if couch.isGroup {
            return store.entries(forExactAudience: couch.memberIDs)
        }

        return store.entries(including: couch.primary.id)
    }

    /// The picks for this couch (`pickEntries(for:)`), resolved to library items as seen by `session`
    /// (the primary user): newest pick first, and the picks everyone on the couch already played last.
    ///
    /// Picks that aren't in the library, or that the primary user can't access, are left out.
    static func pickedItems(
        couch: CouchGroup,
        session: UserSession,
        refreshStore: Bool
    ) async -> [BaseItemDto] {
        let split = await pickedItemsSplit(
            couch: couch,
            session: session,
            refreshStore: refreshStore
        )

        return split.fresh + split.watchedByEveryone
    }

    /// The picks for this couch, like `pickedItems(couch:session:refreshStore:)`, split by whether
    /// everyone on the couch already played them.
    ///
    /// Played picks are kept (kids rewatch favourites), they only make way for the fresh ones.
    /// Only members whose played state could be checked count. Picks stay exempt from the
    /// access and "watched" filters of the other couch rows by design.
    ///
    /// - Returns: Both lists newest pick first.
    static func pickedItemsSplit(
        couch: CouchGroup,
        session: UserSession,
        refreshStore: Bool
    ) async -> (fresh: [BaseItemDto], watchedByEveryone: [BaseItemDto]) {
        let store = Container.shared.audienceWatchlistStore()

        // The store shows its cached list right away. Refresh it from the household's
        // accounts (picks made on another device), unless that happened moments ago.
        // A refresh that is already running is awaited by the store, not repeated.
        let isStale = store.lastRefreshDate.map { Date.now.timeIntervalSince($0) > storeRefreshInterval } ?? true

        if refreshStore, isStale {
            await store.refresh(sessions: session.householdSessions())
        }

        let entries = pickEntries(for: couch)

        guard entries.isNotEmpty else { return (fresh: [], watchedByEveryone: []) }

        let resolvedItems = await store.libraryItems(for: entries, session: session)

        var orderedIDs: [String] = []
        var resolvedItemsByID: [String: BaseItemDto] = [:]

        for entry in entries {
            guard let item = resolvedItems[entry.id],
                  let id = item.id,
                  resolvedItemsByID[id] == nil
            else { continue }

            resolvedItemsByID[id] = item
            orderedIDs.append(id)
        }

        guard orderedIDs.isNotEmpty else { return (fresh: [], watchedByEveryone: []) }

        // Fetch the items again as the primary user: full poster fields,
        // their own user data, and their parental controls.
        let items: [BaseItemDto]
        let primaryResult: [BaseItemDto]?

        do {
            let fetchedItems = try await CouchItemFilter.fetchItems(ids: orderedIDs, session: session)
            let itemsByID = itemsKeyedByID(fetchedItems)

            items = orderedIDs.compactMap { itemsByID[$0] }
            primaryResult = items
        } catch {
            logger.error("Couch: could not fetch the picked items: \(error.localizedDescription)")

            // Without the primary user's own user data, their played state is unknown
            items = orderedIDs.compactMap { resolvedItemsByID[$0] }
            primaryResult = nil
        }

        // The other members' played state, as seen by their own accounts
        let otherSessions = memberSessions(for: couch, primary: session)
        var otherResults: [[BaseItemDto]?] = []

        if otherSessions.isNotEmpty, items.isNotEmpty {
            otherResults = await CouchItemFilter.fetchItems(
                ids: CouchItemFilter.uniqueIDs(of: items),
                seenBy: otherSessions,
                fields: nil,
                enableImages: false
            )
        }

        return splitPlayedByEveryone(items, memberResults: [primaryResult] + otherResults)
    }

    /// Splits items into the ones that not every checked member played yet, and the ones they all played
    /// (`isPlayed == true`), keeping the order within both.
    ///
    /// - Parameter memberResults: Per member, the items as that member sees them, or `nil` when that member
    ///   couldn't be checked. An item a member can't see counts as not played by them.
    /// - Returns: Every item as fresh when no member could be checked.
    static func splitPlayedByEveryone(
        _ items: [BaseItemDto],
        memberResults: [[BaseItemDto]?]
    ) -> (fresh: [BaseItemDto], watchedByEveryone: [BaseItemDto]) {
        let checkedResults = memberResults.compactMap(\.self)

        guard checkedResults.isNotEmpty else { return (fresh: items, watchedByEveryone: []) }

        var playedCounts: [String: Int] = [:]

        for memberItems in checkedResults {
            var countedIDs: Set<String> = []

            for memberItem in memberItems where memberItem.userData?.isPlayed == true {
                guard let id = memberItem.id, countedIDs.insert(id).inserted else { continue }

                playedCounts[id, default: 0] += 1
            }
        }

        var fresh: [BaseItemDto] = []
        var watchedByEveryone: [BaseItemDto] = []

        for item in items {
            if let id = item.id, playedCounts[id, default: 0] >= checkedResults.count {
                watchedByEveryone.append(item)
            } else {
                fresh.append(item)
            }
        }

        return (fresh: fresh, watchedByEveryone: watchedByEveryone)
    }

    // MARK: - Toddler content

    /// Whether the couch has a child and at least one adult (`UserState.isChildAudience`:
    /// marked as a kid, or a server age limit below 12).
    static func hasKidAndAdults(_ couch: CouchGroup) -> Bool {
        couch.members.contains { $0.isChildAudience } && couch.members.contains { !$0.isChildAudience }
    }

    /// Drops toddler content when a child and adults are on the couch together,
    /// unless it was picked for this couch (`pickEntries(for:)`).
    ///
    /// Ratings can't tell a toddler show from a family film, so this uses genres
    /// ("Kids", "Children"). Episodes are judged by their series' genres too.
    ///
    /// Only what the items don't carry is looked up (`toddlerDetails(for:session:)`): the series of episodes,
    /// and items that came without genres, or without the provider ids a pick is matched by.
    static func removingToddlerContent(
        _ items: [BaseItemDto],
        couch: CouchGroup,
        session: UserSession
    ) async -> [BaseItemDto] {
        guard items.isNotEmpty, hasKidAndAdults(couch) else { return items }

        let picks = CouchPicks(couch: couch)

        var lookupIDs: [String] = []
        var lookupIDSet: Set<String> = []

        for item in items {
            if let id = item.id, needsToddlerDetails(item), lookupIDSet.insert(id).inserted {
                lookupIDs.append(id)
            }

            // Episodes rarely carry genres themselves: also look up their series.
            if let seriesID = item.seriesID, lookupIDSet.insert(seriesID).inserted {
                lookupIDs.append(seriesID)
            }
        }

        let details = await toddlerDetails(for: lookupIDs, session: session)

        return items.filter { item in
            let detailItem = item.id.flatMap { details[$0] } ?? item
            let series = item.seriesID.flatMap { details[$0] }

            if picks.contains(detailItem) {
                return true
            }

            if let series, picks.contains(series) {
                return true
            }

            let genres = (detailItem.genres ?? []) + (series?.genres ?? [])

            return !isToddlerContent(genres: genres)
        }
    }

    /// Whether the toddler filter has to look the item up: it came without genres, or it could be a pick
    /// (a movie or a series) and came without the provider ids its TMDB id is read from.
    private static func needsToddlerDetails(_ item: BaseItemDto) -> Bool {
        if item.genres == nil {
            return true
        }

        return AudienceWatchlistEntry.mediaKind(of: item.type) != nil && item.providerIDs == nil
    }

    /// Whether these genres mark toddler content.
    static func isToddlerContent(genres: [String]) -> Bool {
        genres.contains { genre in
            let genre = genre.lowercased()

            return toddlerGenreKeywords.contains { genre.contains($0) }
        }
    }

    // MARK: - Toddler details cache

    /// How long looked up genres and provider ids are reused: the couch rows of one home refresh
    /// look up many of the same series and items.
    private static let toddlerDetailsLifetime: TimeInterval = 60

    /// Looked up items (`.genres` and `.providerIDs` only), by item id, with when they were fetched.
    ///
    /// Genres and provider ids are the item's metadata, the same for every user. Items a user can't access
    /// are never returned, so never cached.
    private static var toddlerDetailsCache: [String: (item: BaseItemDto, fetchedAt: Date)] = [:]

    /// The lookups that are running, by item id, so rows that load at the same time share them.
    private static var toddlerDetailsLookups: [String: Task<[String: BaseItemDto], Never>] = [:]

    /// The items with these ids, with their genres and provider ids, from the cache or fetched as `session`.
    ///
    /// Never throws: a failed lookup is logged, and its items are missing from the result.
    private static func toddlerDetails(
        for ids: [String],
        session: UserSession
    ) async -> [String: BaseItemDto] {
        guard ids.isNotEmpty else { return [:] }

        let now = Date.now
        toddlerDetailsCache = toddlerDetailsCache.filter { now.timeIntervalSince($0.value.fetchedAt) < toddlerDetailsLifetime }

        var details: [String: BaseItemDto] = [:]
        var runningLookups: [Task<[String: BaseItemDto], Never>] = []
        var missingIDs: [String] = []

        for id in ids {
            if let cached = toddlerDetailsCache[id] {
                details[id] = cached.item
            } else if let lookup = toddlerDetailsLookups[id] {
                if !runningLookups.contains(lookup) {
                    runningLookups.append(lookup)
                }
            } else {
                missingIDs.append(id)
            }
        }

        if missingIDs.isNotEmpty {
            let lookupIDs = missingIDs

            let lookup = Task { @MainActor () -> [String: BaseItemDto] in
                var fetched: [String: BaseItemDto] = [:]

                do {
                    let detailItems = try await CouchItemFilter.fetchItems(
                        ids: lookupIDs,
                        session: session,
                        fields: [.genres, .providerIDs],
                        enableImages: false
                    )
                    fetched = CouchHomeSupport.itemsKeyedByID(detailItems)
                } catch {
                    CouchHomeSupport.logger.error("Couch: could not fetch genres for the toddler filter: \(error.localizedDescription)")
                }

                let fetchedAt = Date.now

                for (id, item) in fetched {
                    CouchHomeSupport.toddlerDetailsCache[id] = (item: item, fetchedAt: fetchedAt)
                }

                for id in lookupIDs {
                    CouchHomeSupport.toddlerDetailsLookups[id] = nil
                }

                return fetched
            }

            for id in lookupIDs {
                toddlerDetailsLookups[id] = lookup
            }

            runningLookups.append(lookup)
        }

        let requestedIDs = Set(ids)

        for lookup in runningLookups {
            let fetched = await lookup.value

            for (id, item) in fetched where requestedIDs.contains(id) {
                details[id] = item
            }
        }

        return details
    }

    // MARK: - Helpers

    static func itemsKeyedByID(_ items: [BaseItemDto]) -> [String: BaseItemDto] {
        var itemsByID: [String: BaseItemDto] = [:]

        for item in items {
            guard let id = item.id, itemsByID[id] == nil else { continue }

            itemsByID[id] = item
        }

        return itemsByID
    }
}

/// The watchlist picks for one couch (`CouchHomeSupport.pickEntries(for:)`), matched against library items
/// by Jellyfin id or TMDB id, without any request.
@MainActor
private struct CouchPicks {

    private var itemIDs: Set<String> = []
    /// `"tmdb-movie-862"`-style keys, as `AudienceWatchlistEntry.makeID` builds them.
    private var tmdbKeys: Set<String> = []

    init(couch: CouchGroup) {
        let entries = CouchHomeSupport.pickEntries(for: couch)

        for entry in entries {
            if let jellyfinItemID = entry.jellyfinItemID {
                itemIDs.insert(jellyfinItemID)
            }

            if let tmdbID = entry.tmdbID {
                tmdbKeys.insert(AudienceWatchlistEntry.makeID(tmdbID: tmdbID, kind: entry.kind, jellyfinItemID: nil))
            }
        }
    }

    /// Whether the item (a movie or a series) was picked for this couch.
    ///
    /// Matching by TMDB id needs the item's `providerIDs`.
    func contains(_ item: BaseItemDto) -> Bool {
        if let id = item.id, itemIDs.contains(id) {
            return true
        }

        guard let kind = AudienceWatchlistEntry.mediaKind(of: item.type),
              let tmdbID = AudienceWatchlistEntry.tmdbID(of: item)
        else { return false }

        return tmdbKeys.contains(AudienceWatchlistEntry.makeID(tmdbID: tmdbID, kind: kind, jellyfinItemID: nil))
    }
}
