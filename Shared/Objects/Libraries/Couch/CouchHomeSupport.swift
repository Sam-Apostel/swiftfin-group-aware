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
/// that member is skipped and the error is logged, so a row never fails because of one member.
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
    /// Members without a stored access token have no session and are skipped.
    static func memberSessions(
        for couch: CouchGroup,
        primary: UserSession
    ) -> [UserSession] {
        couch.otherMembers.compactMap { member in
            guard member.id != primary.user.id else { return nil }

            return primary.session(forMemberID: member.id)
        }
    }

    /// Runs one request per session, concurrently.
    ///
    /// - Returns: One result per session, in the order of `sessions`.
    ///   The result is `nil` for a session whose request failed; the error is logged.
    static func perSession(
        _ sessions: [UserSession],
        _ request: @escaping @MainActor (UserSession) async throws -> [BaseItemDto]
    ) async -> [[BaseItemDto]?] {
        await withTaskGroup(of: (Int, [BaseItemDto]?).self) { group in
            for (index, session) in sessions.enumerated() {
                group.addTask { @MainActor in
                    do {
                        let items = try await request(session)
                        return (index, items)
                    } catch {
                        CouchHomeSupport.logger.error(
                            "Couch: request failed for user \(session.user.id): \(error.localizedDescription)"
                        )
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

    /// The watchlist picks tagged for exactly this couch, resolved to library items as seen by `session`
    /// (the primary user), newest pick first.
    ///
    /// Picks that aren't in the library, or that the primary user can't access, are left out.
    static func pickedItems(
        couch: CouchGroup,
        session: UserSession,
        refreshStore: Bool
    ) async -> [BaseItemDto] {
        let store = Container.shared.audienceWatchlistStore()

        // The store shows its cached list right away. Refresh it from the household's
        // accounts (picks made on another device), unless that happened moments ago.
        // A refresh that is already running is awaited by the store, not repeated.
        let isStale = store.lastRefreshDate.map { Date.now.timeIntervalSince($0) > storeRefreshInterval } ?? true

        if refreshStore, isStale {
            await store.refresh(sessions: session.householdSessions())
        }

        let entries = store.entries(forExactAudience: couch.memberIDs)

        guard entries.isNotEmpty else { return [] }

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

        guard orderedIDs.isNotEmpty else { return [] }

        // Fetch the items again as the primary user: full poster fields,
        // their own user data, and their parental controls.
        do {
            let items = try await CouchItemFilter.fetchItems(ids: orderedIDs, session: session)
            let itemsByID = itemsKeyedByID(items)

            return orderedIDs.compactMap { itemsByID[$0] }
        } catch {
            logger.error("Couch: could not fetch the picked items: \(error.localizedDescription)")

            return orderedIDs.compactMap { resolvedItemsByID[$0] }
        }
    }

    // MARK: - Toddler content

    /// Whether the couch has a kid and at least one adult.
    static func hasKidAndAdults(_ couch: CouchGroup) -> Bool {
        couch.members.contains { $0.isKid } && couch.members.contains { !$0.isKid }
    }

    /// Drops toddler content when a kid and adults are on the couch together,
    /// unless it was picked for exactly this couch.
    ///
    /// Ratings can't tell a toddler show from a family film, so this uses genres
    /// ("Kids", "Children"). Episodes are judged by their series' genres too.
    static func removingToddlerContent(
        _ items: [BaseItemDto],
        couch: CouchGroup,
        session: UserSession
    ) async -> [BaseItemDto] {
        guard items.isNotEmpty, hasKidAndAdults(couch) else { return items }

        let picks = CouchPicks(couch: couch)

        // Episodes rarely carry genres themselves: also look up their series.
        var lookupIDs = CouchItemFilter.uniqueIDs(of: items)
        var lookupIDSet = Set(lookupIDs)

        for item in items {
            guard let seriesID = item.seriesID,
                  lookupIDSet.insert(seriesID).inserted
            else { continue }

            lookupIDs.append(seriesID)
        }

        var details: [String: BaseItemDto] = [:]

        do {
            let detailItems = try await CouchItemFilter.fetchItems(
                ids: lookupIDs,
                session: session,
                fields: [.genres, .providerIDs],
                enableImages: false
            )
            details = itemsKeyedByID(detailItems)
        } catch {
            logger.error("Couch: could not fetch genres for the toddler filter: \(error.localizedDescription)")
        }

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

    /// Whether these genres mark toddler content.
    static func isToddlerContent(genres: [String]) -> Bool {
        genres.contains { genre in
            let genre = genre.lowercased()

            return toddlerGenreKeywords.contains { genre.contains($0) }
        }
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

/// The watchlist picks for exactly one couch, matched against library items
/// by Jellyfin id or TMDB id, without any request.
@MainActor
private struct CouchPicks {

    private var itemIDs: Set<String> = []
    /// `"tmdb-movie-862"`-style keys, as `AudienceWatchlistEntry.makeID` builds them.
    private var tmdbKeys: Set<String> = []

    init(couch: CouchGroup) {
        let entries = Container.shared
            .audienceWatchlistStore()
            .entries(forExactAudience: couch.memberIDs)

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
