//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import FactoryKit
import Foundation
import JellyfinAPI
import Logging

/// Everything the couch could watch tonight: the decider's candidates and their items.
struct CouchDeciderPool {

    /// How the pool was made safe for the restricted people on the couch (kids, parental ratings).
    enum KidSafety: Equatable {

        /// Nobody on the couch is restricted.
        case notNeeded

        /// Every candidate was checked with the accounts of these restricted members,
        /// and the server restricts every one of them.
        case verified(names: [String])

        /// These kids have no parental rating on the server: besides their own account's check,
        /// only titles rated PG or lower are suggested (picks excepted).
        case localOnly(names: [String])

        /// These restricted members' accounts couldn't be checked,
        /// so only titles picked for this couch are suggested.
        case limitedToPicks(names: [String])
    }

    /// The candidates, merged, enriched and kid-filtered, in source order:
    /// picks first, then next up, then new, then the library.
    let candidates: [CouchDeciderCandidate]

    /// The enriched item of every candidate, by `CouchDeciderCandidate.id`
    /// (posters, overview, playback).
    let items: [String: BaseItemDto]

    let kidSafety: KidSafety

    /// How many titles the kids' rating ceiling (`KidSafety.localOnly`) left out.
    var removedByKidCeiling: Int = 0

    static let empty = CouchDeciderPool(candidates: [], items: [:], kidSafety: .notNeeded)
}

/// Builds the decider's pool from the couch home's rows: "Picked for …", "Next up together"
/// and "New for all of you", plus random titles from the whole library.
///
/// Reusing the couch libraries means the decider follows the home's rules: every member's own
/// account and access, the played rule (`Defaults[.Couch.hideWatchedByAnyMember]`) and the toddler filter.
@MainActor
enum CouchDeciderCandidateSource {

    /// How many "Next up together" episodes are considered.
    static let nextUpCount = 30

    /// How many "New for all of you" titles are considered.
    static let newForEveryoneCount = 60

    /// How many random library titles are requested (before the couch filters).
    static let libraryCount = 80

    /// The weight scale of a pick everyone on the couch already watched.
    static let watchedByEveryoneWeightScale = 0.2

    /// The highest official rating suggested to a kid without a parental rating on the server.
    static let kidRatingCeiling = "PG"

    /// Ratings Jellyfin treats as no rating at all (`LocalizationManager._unratedValues`).
    /// Jellyfin 10.11+ lets unrated items through `maxOfficialRating`, so they never count as rated.
    private static let unratedValues: Set<String> = ["N/A", "UNRATED", "NOT RATED", "NR"]

    /// The extra fields for the decider's card.
    static let enrichmentFields: [ItemFields] = [.genres, .overview, .taglines, .providerIDs]

    private static let logger = Logger.swiftfin()

    // MARK: - Load

    /// Loads the pool for the couch, as `primary` (the account the app browses as).
    ///
    /// Each source is isolated: a failing source is logged and skipped.
    ///
    /// - Throws: Only when every source failed: "Next up together", "New for all of you" and the library
    ///   threw and there are no picks. (Picks never throw: the watchlist store falls back to its cache.)
    static func load(couch: CouchGroup, primary: UserSession) async throws -> CouchDeciderPool {
        async let pickedLoad = CouchHomeSupport.pickedItemsSplit(couch: couch, session: primary, refreshStore: true)
        async let nextUpLoad = nextUpItems(couch: couch, primary: primary)
        async let newLoad = newForEveryoneItems(couch: couch, primary: primary)
        async let libraryLoad = libraryItems(couch: couch, primary: primary)

        let pickedSplit = await pickedLoad
        let nextUpResult = await nextUpLoad
        let newResult = await newLoad
        let libraryResult = await libraryLoad

        let picked = pickedSplit.fresh + pickedSplit.watchedByEveryone

        if case let .failure(error) = nextUpResult,
           case .failure = newResult,
           case .failure = libraryResult,
           picked.isEmpty
        {
            throw error
        }

        let nextUp = (try? nextUpResult.get()) ?? []
        let newForEveryone = (try? newResult.get()) ?? []
        let library = (try? libraryResult.get()) ?? []

        // The library goes last, so a title that is also new or next up keeps those tags first
        let entries = merge([
            (source: .picked, items: picked),
            (source: .nextUp, items: nextUp),
            (source: .newForEveryone, items: newForEveryone),
            (source: .library, items: library),
        ])

        guard entries.isNotEmpty else {
            return CouchDeciderPool(
                candidates: [],
                items: [:],
                kidSafety: kidSafetyWithoutCandidates(couch: couch, primary: primary)
            )
        }

        let enrichedByID = await enrichedItems(for: entries, primary: primary)
        let watchedPickIDs = Set(pickedSplit.watchedByEveryone.compactMap(\.id))

        var candidates: [CouchDeciderCandidate] = []
        var items: [String: BaseItemDto] = [:]

        for entry in entries {
            guard let id = entry.item.id else { continue }

            let item = enrichedByID[id] ?? entry.item

            guard var newCandidate = Self.candidate(
                for: item,
                sources: entry.sources,
                seriesGenres: item.seriesID.flatMap { enrichedByID[$0]?.genres }
            ) else { continue }

            // Played picks stay (kids rewatch favourites), they only come up less often
            if newCandidate.sources.contains(.picked), watchedPickIDs.contains(id) {
                newCandidate.weightScale = watchedByEveryoneWeightScale
            }

            candidates.append(newCandidate)
            items[newCandidate.id] = item
        }

        // Ratings are judged on the enriched items, and on their shows for episodes
        var ratingItems = enrichedByID

        for (id, item) in items where ratingItems[id] == nil {
            ratingItems[id] = item
        }

        let kidCheck = await kidSafeCandidates(
            candidates,
            couch: couch,
            primary: primary,
            ratingItems: ratingItems
        )

        let safeIDs = Set(kidCheck.candidates.map(\.id))

        return CouchDeciderPool(
            candidates: kidCheck.candidates,
            items: items.filter { safeIDs.contains($0.key) },
            kidSafety: kidCheck.kidSafety,
            removedByKidCeiling: kidCheck.removedByCeiling
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

    /// Random movies and shows from the whole library, so older titles that were never
    /// tagged or recently added come up too.
    ///
    /// The same rules as "New for all of you": every member's access, checked with their own
    /// account (failing closed for restricted members), the played rule and the toddler filter.
    private static func libraryItems(
        couch: CouchGroup,
        primary: UserSession
    ) async -> Result<[BaseItemDto], Error> {
        let playedRule: CouchPlayedRule = Defaults[.Couch.hideWatchedByAnyMember] ? .anyMember : .allMembers

        var parameters = Paths.GetItemsParameters()
        parameters.enableUserData = true
        parameters.fields = PosterSubtitleField.itemFields
        parameters.includeItemTypes = [.movie, .series]
        parameters.isRecursive = true
        parameters.limit = libraryCount
        parameters.sortBy = [.random]
        parameters.userID = primary.user.id

        // The primary user's own watch history is filtered by the server
        if playedRule == .anyMember {
            parameters.isPlayed = false
        }

        do {
            let request = Paths.getItems(parameters: parameters)
            let response = try await primary.client.send(request)

            let unwatched = await CouchItemFilter.filter(
                response.value.items ?? [],
                couch: couch,
                primary: primary,
                excludePlayedBy: playedRule
            )

            let items = await CouchHomeSupport.removingToddlerContent(
                unwatched,
                couch: couch,
                session: primary
            )

            return .success(items)
        } catch {
            logger.error("Couch decider: could not load library titles: \(error.localizedDescription)")

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

    private struct KidCheck {
        var candidates: [CouchDeciderCandidate]
        var kidSafety: CouchDeciderPool.KidSafety
        var removedByCeiling: Int = 0
    }

    /// Whether a restricted member also gets the rating ceiling: a kid without a maximum parental
    /// rating on the server (or whose policy is unknown), so their own account may see anything rated.
    ///
    /// Covers `UserState.isKidWithoutServerLimit`, and also kids whose server access is limited only
    /// by libraries or tags, which don't cap ratings either.
    static func needsRatingCeiling(_ member: UserState) -> Bool {
        member.isKid && member.data.policy?.maxParentalRating == nil
    }

    /// The badge once every restricted member was checked.
    private static func checkedKidSafety(restricted: [UserState]) -> CouchDeciderPool.KidSafety {
        guard restricted.isNotEmpty else { return .notNeeded }

        let ceilingMembers = restricted.filter { needsRatingCeiling($0) }

        // Green only when the server itself restricts every one of them
        guard ceilingMembers.isEmpty else {
            return .localOnly(names: ceilingMembers.map(\.username))
        }

        return .verified(names: restricted.map(\.username))
    }

    /// The badge for an empty pool. There was nothing to check, so the couch rows' own checks
    /// (recorded in `CouchMemberHealth` during this load) say whether the restricted members could be checked.
    private static func kidSafetyWithoutCandidates(
        couch: CouchGroup,
        primary: UserSession
    ) -> CouchDeciderPool.KidSafety {
        let restricted = couch.members.filter(\.isRestricted)

        guard restricted.isNotEmpty else { return .notNeeded }

        let failures = Container.shared.couchMemberHealth().failures(for: couch)

        let uncheckedNames = restricted
            .filter { member in
                primary.session(forMemberID: member.id) == nil || failures[member.id] != nil
            }
            .map(\.username)

        guard uncheckedNames.isEmpty else { return .limitedToPicks(names: uncheckedNames) }

        return checkedKidSafety(restricted: restricted)
    }

    /// Keeps the candidates every restricted member can see, checked with their own account,
    /// so the server's parental controls apply.
    ///
    /// Kids without a parental rating on the server (`needsRatingCeiling(_:)`) are also capped at
    /// `kidRatingCeiling`: the server decides with its rating tables, asked with the kid's own account.
    /// When that request fails, `KidRatings.isKidSafe` decides instead. Either way, a title without
    /// a rating on the item or its show is left out.
    ///
    /// Picked candidates always pass: they were tagged for this exact couch.
    /// Fails closed: when a restricted member has no session or their check failed, only picks are kept.
    private static func kidSafeCandidates(
        _ candidates: [CouchDeciderCandidate],
        couch: CouchGroup,
        primary: UserSession,
        ratingItems: [String: BaseItemDto]
    ) async -> KidCheck {
        let restricted = couch.members.filter(\.isRestricted)

        guard restricted.isNotEmpty else {
            return KidCheck(candidates: candidates, kidSafety: .notNeeded)
        }

        let names = restricted.map(\.username)
        let picksOnly = candidates.filter { $0.sources.contains(.picked) }
        let checkedSafety = checkedKidSafety(restricted: restricted)

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

            return KidCheck(candidates: picksOnly, kidSafety: .limitedToPicks(names: membersWithoutSession))
        }

        let idsToCheck = candidates
            .filter { !$0.sources.contains(.picked) }
            .map(\.id)

        guard idsToCheck.isNotEmpty else {
            return KidCheck(candidates: candidates, kidSafety: checkedSafety)
        }

        let results = await CouchItemFilter.fetchItems(
            ids: idsToCheck,
            seenBy: checkedSessions,
            fields: nil,
            enableImages: false
        )

        guard results.count == restricted.count else {
            logger.error("Couch decider: unexpected access check results, suggesting picks only")

            return KidCheck(candidates: picksOnly, kidSafety: .limitedToPicks(names: names))
        }

        var failedNames: [String] = []

        for (member, memberItems) in zip(restricted, results) where memberItems == nil {
            failedNames.append(member.username)
        }

        guard failedNames.isEmpty else {
            logger.error("Couch decider: could not check a restricted member's access, suggesting picks only")

            return KidCheck(candidates: picksOnly, kidSafety: .limitedToPicks(names: failedNames))
        }

        var visibleToAll = Set(idsToCheck)

        for memberItems in results {
            visibleToAll.formIntersection((memberItems ?? []).compactMap(\.id))
        }

        // The rating ceiling, for each kid without a parental rating on the server
        let visibleCount = visibleToAll.count

        for (member, session) in zip(restricted, checkedSessions) where needsRatingCeiling(member) {
            let ids = idsToCheck.filter { visibleToAll.contains($0) }

            guard ids.isNotEmpty else { break }

            let allowedIDs = await ratedKidSafeIDs(
                ids,
                kidSession: session,
                ratingItems: ratingItems
            )

            visibleToAll.formIntersection(allowedIDs)
        }

        let safeCandidates = candidates.filter { candidate in
            candidate.sources.contains(.picked) || visibleToAll.contains(candidate.id)
        }

        return KidCheck(
            candidates: safeCandidates,
            kidSafety: checkedSafety,
            removedByCeiling: visibleCount - visibleToAll.count
        )
    }

    /// The ids of the titles rated `kidRatingCeiling` or lower, as the server judges them for this kid.
    ///
    /// Falls back to `KidRatings.isKidSafe` when the request fails.
    /// Fails closed: titles without a rating on the item or its show are never returned.
    private static func ratedKidSafeIDs(
        _ ids: [String],
        kidSession: UserSession,
        ratingItems: [String: BaseItemDto]
    ) async -> Set<String> {
        do {
            let serverItems = try await fetchRatedItems(ids: ids, session: kidSession)

            var allowedIDs: Set<String> = []

            for serverItem in serverItems {
                guard let id = serverItem.id else { continue }

                let item = ratingItems[id] ?? serverItem
                let knownRatings = itemRatings(of: item, series: series(of: item, in: ratingItems))
                    .filter { !unratedValues.contains(KidRatings.normalized($0)) }

                // Jellyfin 10.11+ lets unrated titles through `maxOfficialRating`
                if knownRatings.isNotEmpty {
                    allowedIDs.insert(id)
                }
            }

            return allowedIDs
        } catch {
            logger.error(
                "Couch decider: could not check ratings with the kid's account, using the local list: \(error.localizedDescription)"
            )

            var allowedIDs: Set<String> = []

            for id in ids {
                guard let item = ratingItems[id] else { continue }

                let ratings = itemRatings(of: item, series: series(of: item, in: ratingItems))

                if ratings.isNotEmpty, ratings.allSatisfy({ KidRatings.isKidSafe($0) }) {
                    allowedIDs.insert(id)
                }
            }

            return allowedIDs
        }
    }

    /// The items with these ids that the kid's account sees with a rating up to `kidRatingCeiling`.
    ///
    /// `maxOfficialRating` replaces the account's own maximum, so it is only sent for kids without one
    /// (`needsRatingCeiling(_:)`), and the result is intersected with their own access check.
    private static func fetchRatedItems(
        ids: [String],
        session: UserSession
    ) async throws -> [BaseItemDto] {
        var result: [BaseItemDto] = []
        var start = 0

        while start < ids.count {
            let end = min(start + CouchItemFilter.maxIDsPerRequest, ids.count)
            let chunk = Array(ids[start ..< end])
            start = end

            var parameters = Paths.GetItemsParameters()
            parameters.enableImages = false
            parameters.enableUserData = false
            parameters.hasParentalRating = true
            parameters.ids = chunk
            parameters.limit = chunk.count
            parameters.maxOfficialRating = kidRatingCeiling
            parameters.userID = session.user.id

            let request = Paths.getItems(parameters: parameters)
            let response = try await session.client.send(request)

            result.append(contentsOf: response.value.items ?? [])
        }

        return result
    }

    /// The show of an episode, when it was fetched.
    private static func series(of item: BaseItemDto, in items: [String: BaseItemDto]) -> BaseItemDto? {
        guard item.type == .episode else { return nil }

        return item.seriesID.flatMap { items[$0] }
    }

    /// The ratings that apply to an item: its own and its show's (each custom rating first, as Jellyfin does).
    private static func itemRatings(of item: BaseItemDto, series: BaseItemDto?) -> [String] {
        [item, series].compactMap { ratedItem -> String? in
            guard let ratedItem else { return nil }

            return ratedItem.customRating?.nilIfBlank ?? ratedItem.officialRating?.nilIfBlank
        }
    }
}
