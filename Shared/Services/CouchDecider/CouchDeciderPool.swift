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

/// Everything the couch could watch tonight: the decider's candidates and their items.
struct CouchDeciderPool {

    /// How the pool was made safe for the restricted people on the couch (kids, parental ratings).
    enum KidSafety: Equatable {

        /// Nobody on the couch is restricted.
        case notNeeded

        /// Every candidate was checked with the accounts of these restricted members.
        case verified(names: [String])

        /// These restricted members' accounts couldn't be checked,
        /// so only titles picked for this couch are suggested.
        case limitedToPicks(names: [String])
    }

    /// The candidates, merged, enriched and kid-filtered, in source order:
    /// picks first, then next up, then new.
    let candidates: [CouchDeciderCandidate]

    /// The enriched item of every candidate, by `CouchDeciderCandidate.id`
    /// (posters, overview, playback).
    let items: [String: BaseItemDto]

    let kidSafety: KidSafety

    static let empty = CouchDeciderPool(candidates: [], items: [:], kidSafety: .notNeeded)
}

/// Builds the decider's pool from the couch home's rows: "Picked for …", "Next up together"
/// and "New for all of you".
///
/// Reusing the couch libraries means the decider follows the home's rules: every member's own
/// account and access, the played rule (`Defaults[.Couch.hideWatchedByAnyMember]`) and the toddler filter.
@MainActor
enum CouchDeciderCandidateSource {

    /// How many "Next up together" episodes are considered.
    static let nextUpCount = 30

    /// How many "New for all of you" titles are considered.
    static let newForEveryoneCount = 60

    /// The extra fields for the decider's card.
    static let enrichmentFields: [ItemFields] = [.genres, .overview, .taglines, .providerIDs]

    private static let logger = Logger.swiftfin()

    // MARK: - Load

    /// Loads the pool for the couch, as `primary` (the account the app browses as).
    ///
    /// Each source is isolated: a failing source is logged and skipped.
    ///
    /// - Throws: Only when every source failed: "Next up together" and "New for all of you" threw
    ///   and there are no picks. (Picks never throw: the watchlist store falls back to its cache.)
    static func load(couch: CouchGroup, primary: UserSession) async throws -> CouchDeciderPool {
        async let pickedLoad = CouchHomeSupport.pickedItems(couch: couch, session: primary, refreshStore: true)
        async let nextUpLoad = nextUpItems(couch: couch, primary: primary)
        async let newLoad = newForEveryoneItems(couch: couch, primary: primary)

        let picked = await pickedLoad
        let nextUpResult = await nextUpLoad
        let newResult = await newLoad

        if case let .failure(error) = nextUpResult, case .failure = newResult, picked.isEmpty {
            throw error
        }

        let nextUp = (try? nextUpResult.get()) ?? []
        let newForEveryone = (try? newResult.get()) ?? []

        let entries = merge([
            (source: .picked, items: picked),
            (source: .nextUp, items: nextUp),
            (source: .newForEveryone, items: newForEveryone),
        ])

        guard entries.isNotEmpty else { return .empty }

        let enrichedByID = await enrichedItems(for: entries, primary: primary)

        var candidates: [CouchDeciderCandidate] = []
        var items: [String: BaseItemDto] = [:]

        for entry in entries {
            guard let id = entry.item.id else { continue }

            let item = enrichedByID[id] ?? entry.item

            guard let newCandidate = Self.candidate(
                for: item,
                sources: entry.sources,
                seriesGenres: item.seriesID.flatMap { enrichedByID[$0]?.genres }
            ) else { continue }

            candidates.append(newCandidate)
            items[newCandidate.id] = item
        }

        let (safeCandidates, kidSafety) = await kidSafeCandidates(
            candidates,
            couch: couch,
            primary: primary
        )

        let safeIDs = Set(safeCandidates.map(\.id))

        return CouchDeciderPool(
            candidates: safeCandidates,
            items: items.filter { safeIDs.contains($0.key) },
            kidSafety: kidSafety
        )
    }

    // MARK: - Candidates

    /// The candidate for a movie, video, show or episode, or `nil` for any other item,
    /// an item without an id, or a missing item.
    static func candidate(
        for item: BaseItemDto,
        sources: Set<CouchDeciderCandidate.Source>
    ) -> CouchDeciderCandidate? {
        candidate(for: item, sources: sources, seriesGenres: nil)
    }

    /// - Parameter seriesGenres: The genres of an episode's show, used when the episode has none itself.
    private static func candidate(
        for item: BaseItemDto,
        sources: Set<CouchDeciderCandidate.Source>,
        seriesGenres: [String]?
    ) -> CouchDeciderCandidate? {
        guard let id = item.id, !item.isMissing else { return nil }

        let kind: CouchDeciderCandidate.Kind

        switch item.type {
        case .movie, .video:
            kind = .movie
        case .series:
            kind = .series
        case .episode:
            kind = .episode
        default:
            return nil
        }

        let title: String = if kind == .episode, let seriesName = item.seriesName, seriesName.isNotEmpty {
            seriesName
        } else {
            item.displayTitle
        }

        let runtime: TimeInterval? = if let ticks = item.runTimeTicks, ticks > 0 {
            TimeInterval(ticks) / 10_000_000
        } else {
            nil
        }

        var genres = item.genres ?? []

        if kind == .episode, genres.isEmpty, let seriesGenres {
            genres = seriesGenres
        }

        return CouchDeciderCandidate(
            id: id,
            title: title,
            kind: kind,
            runtime: runtime,
            genres: genres,
            year: item.productionYear,
            sources: sources
        )
    }

    // MARK: - Sources

    private static func nextUpItems(
        couch: CouchGroup,
        primary: UserSession
    ) async -> Result<[BaseItemDto], Error> {
        do {
            let items = try await CouchNextUpLibrary(couch: couch).retrievePage(
                environment: Empty(),
                pageState: LibraryPageState(pageOffset: 0, pageSize: nextUpCount, userSession: primary)
            )

            return .success(items)
        } catch {
            logger.error("Couch decider: could not load next up together: \(error.localizedDescription)")

            return .failure(error)
        }
    }

    private static func newForEveryoneItems(
        couch: CouchGroup,
        primary: UserSession
    ) async -> Result<[BaseItemDto], Error> {
        do {
            let items = try await CouchNewForEveryoneLibrary(couch: couch).retrievePage(
                environment: Empty(),
                pageState: LibraryPageState(pageOffset: 0, pageSize: newForEveryoneCount, userSession: primary)
            )

            return .success(items)
        } catch {
            logger.error("Couch decider: could not load new for all of you: \(error.localizedDescription)")

            return .failure(error)
        }
    }

    // MARK: - Merge

    private struct Entry {
        var item: BaseItemDto
        var sources: Set<CouchDeciderCandidate.Source>
    }

    /// Merges the sources by item id, in order, and unions the sources of duplicates.
    ///
    /// Items without an id and missing items are dropped. A show whose episode is also in the pool
    /// (a "New" show that is in "Next up together") is replaced by that episode, which plays right away;
    /// the episode takes over the show's sources.
    private static func merge(
        _ lists: [(source: CouchDeciderCandidate.Source, items: [BaseItemDto])]
    ) -> [Entry] {
        var entries: [Entry] = []
        var indexByID: [String: Int] = [:]

        for list in lists {
            for item in list.items {
                guard let id = item.id, !item.isMissing else { continue }

                if let index = indexByID[id] {
                    entries[index].sources.insert(list.source)
                } else {
                    indexByID[id] = entries.count
                    entries.append(Entry(item: item, sources: [list.source]))
                }
            }
        }

        var episodeIndexBySeriesID: [String: Int] = [:]

        for (index, entry) in entries.enumerated() where entry.item.type == .episode {
            guard let seriesID = entry.item.seriesID, episodeIndexBySeriesID[seriesID] == nil else { continue }

            episodeIndexBySeriesID[seriesID] = index
        }

        guard episodeIndexBySeriesID.isNotEmpty else { return entries }

        var replacedIndices: Set<Int> = []

        for index in entries.indices where entries[index].item.type == .series {
            guard let seriesID = entries[index].item.id,
                  let episodeIndex = episodeIndexBySeriesID[seriesID]
            else { continue }

            entries[episodeIndex].sources.formUnion(entries[index].sources)
            replacedIndices.insert(index)
        }

        return entries.indices
            .filter { !replacedIndices.contains($0) }
            .map { entries[$0] }
    }

    // MARK: - Enrich

    /// The entries' items (and the shows of episodes, for their genres) fetched again as the primary user,
    /// with the card's extra fields, by id.
    ///
    /// Returns `[:]` when the request fails: the pool then uses the items as the rows returned them.
    private static func enrichedItems(
        for entries: [Entry],
        primary: UserSession
    ) async -> [String: BaseItemDto] {
        var ids = entries.compactMap(\.item.id)
        var seenIDs = Set(ids)

        for entry in entries where entry.item.type == .episode {
            guard let seriesID = entry.item.seriesID, seenIDs.insert(seriesID).inserted else { continue }

            ids.append(seriesID)
        }

        do {
            let items = try await CouchItemFilter.fetchItems(
                ids: ids,
                session: primary,
                fields: enrichmentFields,
                enableImages: true
            )

            return CouchHomeSupport.itemsKeyedByID(items)
        } catch {
            logger.error("Couch decider: could not fetch item details: \(error.localizedDescription)")

            return [:]
        }
    }

    // MARK: - Kid safety

    /// Keeps the candidates every restricted member can see, checked with their own account,
    /// so the server's parental controls apply.
    ///
    /// Picked candidates always pass: they were tagged for this exact couch.
    /// Fails closed: when a restricted member has no session or their check failed, only picks are kept.
    private static func kidSafeCandidates(
        _ candidates: [CouchDeciderCandidate],
        couch: CouchGroup,
        primary: UserSession
    ) async -> ([CouchDeciderCandidate], CouchDeciderPool.KidSafety) {
        let restricted = couch.members.filter(\.isRestricted)

        guard restricted.isNotEmpty else { return (candidates, .notNeeded) }

        let names = restricted.map(\.username)
        let picksOnly = candidates.filter { $0.sources.contains(.picked) }

        var checkedSessions: [UserSession] = []
        var membersWithoutSession: [String] = []

        for member in restricted {
            if let session = primary.session(forMemberID: member.id) {
                checkedSessions.append(session)
            } else {
                membersWithoutSession.append(member.username)
            }
        }

        guard membersWithoutSession.isEmpty else {
            logger.error("Couch decider: no stored session for a restricted member, suggesting picks only")

            return (picksOnly, .limitedToPicks(names: membersWithoutSession))
        }

        let idsToCheck = candidates
            .filter { !$0.sources.contains(.picked) }
            .map(\.id)

        guard idsToCheck.isNotEmpty else { return (candidates, .verified(names: names)) }

        let results = await CouchItemFilter.fetchItems(
            ids: idsToCheck,
            seenBy: checkedSessions,
            fields: nil,
            enableImages: false
        )

        guard results.count == restricted.count else {
            logger.error("Couch decider: unexpected access check results, suggesting picks only")

            return (picksOnly, .limitedToPicks(names: names))
        }

        var failedNames: [String] = []

        for (member, memberItems) in zip(restricted, results) where memberItems == nil {
            failedNames.append(member.username)
        }

        guard failedNames.isEmpty else {
            logger.error("Couch decider: could not check a restricted member's access, suggesting picks only")

            return (picksOnly, .limitedToPicks(names: failedNames))
        }

        var visibleToAll = Set(idsToCheck)

        for memberItems in results {
            visibleToAll.formIntersection((memberItems ?? []).compactMap(\.id))
        }

        let safeCandidates = candidates.filter { candidate in
            candidate.sources.contains(.picked) || visibleToAll.contains(candidate.id)
        }

        return (safeCandidates, .verified(names: names))
    }
}
