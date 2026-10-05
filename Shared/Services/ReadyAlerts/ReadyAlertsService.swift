//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import FactoryKit
import Foundation
import JellyfinAPI
import Logging

extension Container {

    var readyAlertsService: Factory<ReadyAlertsService> {
        self { @MainActor in ReadyAlertsService() }
            .singleton
    }
}

/// Works out which household wishes became playable: "Toy Story is ready for Sam, Lisa & Tuur".
///
/// Candidates are the "Who's it for?" watchlist entries and the household's Seerr requests.
/// A candidate arrived when the library added it after it was wished for (see `ReadyAlertRules.arrivalDate`),
/// which every device derives the same way from server data. Nothing new is synced.
///
/// What this device already told whom is kept per server in a `ReadyAlertLedger` (app suite),
/// so the home row, the banner and the notifications only ask this service and record what they announced.
///
/// Never throws: failures are logged and the last known arrivals are kept.
@MainActor
final class ReadyAlertsService: ObservableObject {

    /// All audiences, newest arrival first, within `ReadyAlertRules.arrivalWindow`.
    @Published
    private(set) var arrivals: [ReadyArrival] = []
    @Published
    private(set) var lastRefreshDate: Date?

    /// `refresh(session:force:)` does nothing this soon after the last refresh, unless forced.
    static let refreshInterval: TimeInterval = 5 * 60

    /// The watchlist store is refreshed first when its last refresh is older than this.
    static let storeRefreshInterval: TimeInterval = 60

    /// The fields the arrival rules and the poster views need.
    static let itemFields: [ItemFields] = PosterSubtitleField.itemFields + [.dateCreated, .dateLastMediaAdded, .providerIDs]

    let logger = Logger.swiftfin()

    /// The server the arrivals and the ledger belong to.
    private var serverID: String?
    /// The user the items were fetched as.
    private var refreshedUserID: String?
    /// `nil` until the first successful refresh of this server on this device (then it's seeded).
    private var ledger: ReadyAlertLedger?
    /// The fetched candidate items, by Jellyfin item id, as seen by `refreshedUserID`.
    private var itemsByID: [String: BaseItemDto] = [:]
    private var refreshTask: Task<Void, Never>?
    /// The server this service last refreshed the watchlist store for.
    private var storeRefreshServerID: String?

    init() {}

    // MARK: - Refresh

    /// Recomputes the arrivals for `session`'s server, with the items fetched as `session.user`
    /// (their library access and parental controls apply).
    ///
    /// Does nothing within `refreshInterval` of the last refresh of the same user unless `force`.
    /// A refresh that is already running is awaited instead of starting a second one.
    func refresh(session: UserSession, force: Bool = false) async {
        if let refreshTask {
            await refreshTask.value
            return
        }

        let isSameAccount = serverID == session.server.id && refreshedUserID == session.user.id

        if force == false, isSameAccount, let lastRefreshDate,
           Date.now.timeIntervalSince(lastRefreshDate) < Self.refreshInterval
        {
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }

            await self.performRefresh(session: session)
        }
        refreshTask = task

        await task.value

        refreshTask = nil
    }

    // MARK: - Queries

    /// The item of an arrival, as fetched for the refreshing session's user.
    func item(for arrival: ReadyArrival) -> BaseItemDto? {
        itemsByID[arrival.jellyfinItemID]
    }

    /// The arrivals a couch of `memberIDs` should see (`ReadyAlertRules.isVisible`), newest first.
    func arrivals(forMembers memberIDs: Set<String>) -> [ReadyArrival] {
        arrivals.filter { ReadyAlertRules.isVisible(audience: $0.audience, forMembers: memberIDs) }
    }

    /// The visible arrivals that some member wasn't told about yet on this device.
    func unannouncedArrivals(forMembers memberIDs: Set<String>) -> [ReadyArrival] {
        arrivals(forMembers: memberIDs).filter { arrival in
            memberIDs.contains { isAnnounced(arrival, to: $0) == false }
        }
    }

    /// The arrivals for any of `userIDs` that one of them (in the audience) wasn't told about yet on this device.
    func unannouncedArrivals(notifying userIDs: Set<String>) -> [ReadyArrival] {
        arrivals.filter { arrival in
            let targets = arrival.audience.intersection(userIDs)

            return targets.contains { isAnnounced(arrival, to: $0) == false }
        }
    }

    /// Records that the audience members among `userIDs` were told about these arrivals on this device.
    func markAnnounced(_ announcedArrivals: [ReadyArrival], to userIDs: Set<String>) {
        guard var ledger, let serverID else { return }

        let now = Date.now
        var didChange = false

        for arrival in announcedArrivals {
            let told = arrival.audience.intersection(userIDs)
            guard told.isEmpty == false else { continue }

            ledger.markAnnounced(arrival.id, to: told, at: now)
            didChange = true
        }

        guard didChange else { return }

        objectWillChange.send()
        self.ledger = ledger
        Self.saveLedger(ledger, serverID: serverID)
    }

    // MARK: - Messages

    /// "Toy Story is ready for Lisa, Sam & Tuur" (names sorted), or "Toy Story is ready" when no name is known.
    func message(for arrival: ReadyArrival) -> String {
        let names = Self.names(of: arrival.audience)

        guard names.isEmpty == false else {
            return L10n.ReadyAlerts.ready(arrival.title)
        }

        return L10n.ReadyAlerts.readyFor(arrival.title, names: L10n.Audience.joinedNames(names))
    }

    /// One arrival: `message(for:)`. More: "Toy Story and 2 more are ready". None: an empty string.
    func summaryMessage(for arrivals: [ReadyArrival]) -> String {
        guard let first = arrivals.first else { return "" }
        guard arrivals.count > 1 else { return message(for: first) }

        return L10n.ReadyAlerts.andMoreReady(first.title, count: arrivals.count - 1)
    }
}

// MARK: - Refresh

extension ReadyAlertsService {

    /// A wish that may arrive. Several candidates can point at the same item; `ReadyAlertRules.publishable` keeps one.
    struct Candidate {
        /// The arrival id (`"w:…"` / `"r:…"`), also the ledger's sighting id.
        let id: String
        let source: ReadyArrival.Source
        let watchlistEntryID: String?
        /// Normalized Jellyfin item id (`normalizedItemID`), `nil` when it isn't in the library.
        var itemKey: String?
        let audience: Set<String>
        let wishedAt: Date
        /// A Seerr request newer than the wish: media added to a series after it counts too.
        let usesLastMediaAdded: Bool
    }

    private func performRefresh(session: UserSession) async {
        // Touching the client of a user without a token would hit `UserState.accessToken`'s assertion
        guard session.user.storedAccessToken != nil else {
            logger.warning("Ready alerts: refresh skipped, user \(session.user.id) has no access token on this device")
            return
        }

        let serverID = session.server.id
        activateServer(id: serverID)

        let now = Date.now
        let householdUserIDs = Set(
            StoredValues[.User.users]
                .filter { $0.serverID == serverID }
                .map(\.id)
        )

        // Watchlist: refreshed first unless that happened moments ago (for this server)
        let store = Container.shared.audienceWatchlistStore()
        let isStoreStale = storeRefreshServerID != serverID
            || store.lastRefreshDate.map { now.timeIntervalSince($0) > Self.storeRefreshInterval } ?? true

        if isStoreStale {
            await store.refresh(sessions: session.householdSessions())
            storeRefreshServerID = serverID
        }

        let entries = store.entries

        // Seerr requests (empty without Seerr, or for a session that isn't the current one)
        let requests = await seerrRequests(session: session, householdUserIDs: householdUserIDs)

        // Watchlist entries → library items, as seen by the session's user
        let entryItems = await store.libraryItems(for: entries, session: session)
        let entryItemKeys = entryItems.compactMapValues { $0.id.map(Self.normalizedItemID) }

        let (candidates, unavailableRequestIDs) = Self.makeCandidates(
            entries: entries,
            entryItemKeys: entryItemKeys,
            requests: requests,
            householdUserIDs: householdUserIDs
        )

        // One fetch, as the session's user, with the date fields
        let itemIDs = Array(Set(candidates.compactMap(\.itemKey))).sorted()
        let items: [BaseItemDto]

        do {
            items = try await CouchItemFilter.fetchItems(ids: itemIDs, session: session, fields: Self.itemFields)
        } catch {
            logger.error("Ready alerts: fetching the library items failed: \(error.localizedDescription)")
            return
        }

        // Another server became active while fetching: don't mix the results
        guard self.serverID == serverID else { return }

        var itemsByKey: [String: BaseItemDto] = [:]
        for item in items {
            guard let id = item.id else { continue }

            itemsByKey[Self.normalizedItemID(id)] = item
        }

        // Sightings, then arrivals
        let isFirstRun = self.ledger == nil
        var updatedLedger = self.ledger ?? ReadyAlertLedger(createdAt: now)

        for candidate in candidates {
            let isAvailable = candidate.itemKey.flatMap { itemsByKey[$0] } != nil
            updatedLedger.recordSighting(candidate.id, isAvailable: isAvailable, at: now)
        }
        for requestID in unavailableRequestIDs {
            updatedLedger.recordSighting(requestID, isAvailable: false, at: now)
        }

        var allArrivals: [ReadyArrival] = []

        for candidate in candidates {
            guard let itemKey = candidate.itemKey,
                  let item = itemsByKey[itemKey],
                  let itemID = item.id else { continue }
            guard let arrivedAt = ReadyAlertRules.arrivalDate(
                isSeries: item.type == .series,
                usesLastMediaAdded: candidate.usesLastMediaAdded,
                dateCreated: item.dateCreated,
                dateLastMediaAdded: item.dateLastMediaAdded,
                wishedAt: candidate.wishedAt,
                firstSeenAvailable: updatedLedger.firstSeenAvailable[candidate.id]
            ) else { continue }

            allArrivals.append(
                ReadyArrival(
                    id: candidate.id,
                    source: candidate.source,
                    watchlistEntryID: candidate.watchlistEntryID,
                    jellyfinItemID: itemID,
                    title: item.displayTitle,
                    audience: candidate.audience,
                    wishedAt: candidate.wishedAt,
                    arrivedAt: arrivedAt
                )
            )
        }

        let published = ReadyAlertRules.publishable(allArrivals, now: now)

        // Seeding is measured from the ledger's creation, not only on its first refresh: arrivals this
        // device first sees later (no Seerr on a cold background launch, a failed lookup) that landed more
        // than 24 h before it started tracking are old news too, so they never flood a later refresh.
        let seedCutoff = updatedLedger.createdAt.addingTimeInterval(-ReadyAlertRules.seedSilenceInterval)
        let unseededArrivals = published.filter { arrival in
            arrival.arrivedAt < seedCutoff
                && arrival.audience.contains { updatedLedger.isAnnounced(arrival.id, to: $0) == false }
        }
        updatedLedger.seed(with: unseededArrivals, now: now)

        // Without Seerr (no current session, network error) the request candidates are missing:
        // keep their records, or an ongoing request would be announced again once Seerr is back.
        var keptIDs = Set(candidates.map(\.id)).union(unavailableRequestIDs)
        if requests.isEmpty {
            let recordIDs = Set(updatedLedger.announced.keys)
                .union(updatedLedger.seenUnavailable.keys)
                .union(updatedLedger.firstSeenAvailable.keys)

            keptIDs.formUnion(recordIDs.filter { $0.hasPrefix("r:") })
        }

        updatedLedger.prune(now: now, keeping: keptIDs)

        self.ledger = updatedLedger
        Self.saveLedger(updatedLedger, serverID: serverID)

        var publishedItems: [String: BaseItemDto] = [:]
        for arrival in published {
            if let item = itemsByKey[Self.normalizedItemID(arrival.jellyfinItemID)] {
                publishedItems[arrival.jellyfinItemID] = item
            }
        }

        itemsByID = publishedItems
        refreshedUserID = session.user.id
        lastRefreshDate = .now

        if arrivals != published {
            arrivals = published
        } else if isFirstRun || unseededArrivals.isNotEmpty {
            // The ledger changed what's unannounced
            objectWillChange.send()
        }

        logger.info("Ready alerts: \(published.count) arrival(s) from \(candidates.count) candidate(s)")
    }

    /// Watchlist candidates (`"w:<entry id>"`) plus Seerr request candidates (`"r:<request id>"`).
    ///
    /// - Returns: the candidates, and the ids of household requests that aren't available yet (for the sightings).
    private static func makeCandidates(
        entries: [AudienceWatchlistEntry],
        entryItemKeys: [String: String],
        requests: [SeerrRequest],
        householdUserIDs: Set<String>
    ) -> (candidates: [Candidate], unavailableRequestIDs: Set<String>) {
        var candidates: [Candidate] = []
        var candidateIndexByEntryID: [String: Int] = [:]
        var unavailableRequestIDs: Set<String> = []

        for entry in entries {
            candidateIndexByEntryID[entry.id] = candidates.count
            candidates.append(
                Candidate(
                    id: ReadyArrival.watchlistID(entryID: entry.id),
                    source: .watchlist,
                    watchlistEntryID: entry.id,
                    itemKey: entryItemKeys[entry.id] ?? entry.jellyfinItemID.map(normalizedItemID),
                    audience: entry.audience,
                    wishedAt: entry.addedAt,
                    usesLastMediaAdded: false
                )
            )
        }

        let entriesByID = Dictionary(entries.map { ($0.id, $0) }) { first, _ in first }

        for request in requests where request.status != .declined {
            guard let media = request.media else { continue }
            guard media.status.isAvailable, let mediaItemID = media.jellyfinMediaId else {
                unavailableRequestIDs.insert(ReadyArrival.requestID(request.id))
                continue
            }

            let itemKey = normalizedItemID(mediaItemID)
            let entry = joinedEntry(of: request, media: media, itemKey: itemKey, entries: entries, entriesByID: entriesByID)

            if let entry {
                // The entry is the wish; Seerr knows where it is in the library when the TMDB lookup didn't
                if let index = candidateIndexByEntryID[entry.id], candidates[index].itemKey == nil {
                    candidates[index].itemKey = itemKey
                }

                // A series request newer than the entry (a new season) arrives on its own
                let isSeries = request.type == .tv || entry.kind == .tv

                if isSeries, let createdAt = request.createdAt, createdAt > entry.addedAt {
                    candidates.append(
                        Candidate(
                            id: ReadyArrival.requestID(request.id),
                            source: .seerrRequest,
                            watchlistEntryID: entry.id,
                            itemKey: itemKey,
                            audience: entry.audience,
                            wishedAt: createdAt,
                            usesLastMediaAdded: true
                        )
                    )
                }
                continue
            }

            // No entry: the requester is the audience, if they're in the household
            let audience = householdUserIDs.filter { request.requestedBy?.matches(jellyfinUserID: $0) == true }

            guard audience.isEmpty == false else { continue }

            candidates.append(
                Candidate(
                    id: ReadyArrival.requestID(request.id),
                    source: .seerrRequest,
                    watchlistEntryID: nil,
                    itemKey: itemKey,
                    audience: audience,
                    wishedAt: request.createdAt ?? .distantPast,
                    usesLastMediaAdded: request.createdAt != nil
                )
            )
        }

        return (candidates, unavailableRequestIDs)
    }

    /// The watchlist entry for the request's title: by TMDB id, else by Jellyfin item id.
    private static func joinedEntry(
        of request: SeerrRequest,
        media: SeerrMediaInfo,
        itemKey: String,
        entries: [AudienceWatchlistEntry],
        entriesByID: [String: AudienceWatchlistEntry]
    ) -> AudienceWatchlistEntry? {
        if let tmdbID = media.tmdbId {
            let kinds: [AudienceWatchlistEntry.MediaKind] = if let type = request.type,
                                                               let kind = AudienceWatchlistEntry.MediaKind(rawValue: type.rawValue)
            {
                [kind]
            } else {
                [.movie, .tv]
            }

            for kind in kinds {
                let id = AudienceWatchlistEntry.makeID(tmdbID: tmdbID, kind: kind, jellyfinItemID: nil)

                if let entry = entriesByID[id] {
                    return entry
                }
            }
        }

        return entries.first { entry in
            entry.jellyfinItemID.map(normalizedItemID) == itemKey
        }
    }

    /// Jellyfin ids compared without case and dashes (Seerr stores the 32-character hex form).
    static func normalizedItemID(_ id: String) -> String {
        id.replacing("-", with: "").lowercased()
    }

    /// Usernames of the known users among `userIDs`, sorted.
    private static func names(of userIDs: Set<String>) -> [String] {
        StoredValues[.User.users]
            .filter { userIDs.contains($0.id) }
            .map(\.username)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func isAnnounced(_ arrival: ReadyArrival, to userID: String) -> Bool {
        ledger?.isAnnounced(arrival.id, to: userID) ?? false
    }
}

// MARK: - Ledger storage

extension ReadyAlertsService {

    private static func ledgerKey(serverID: String) -> String {
        "sgw.readyAlerts.ledger.\(serverID)"
    }

    /// Switches to `id`'s arrivals and ledger when the server changes.
    private func activateServer(id: String) {
        guard serverID != id else { return }

        serverID = id
        refreshedUserID = nil
        lastRefreshDate = nil
        itemsByID = [:]
        arrivals = []
        ledger = Self.loadLedger(serverID: id)
    }

    private static func loadLedger(serverID: String) -> ReadyAlertLedger? {
        guard let data = UserDefaults.appSuite.data(forKey: ledgerKey(serverID: serverID)) else { return nil }

        return try? JSONDecoder().decode(ReadyAlertLedger.self, from: data)
    }

    private static func saveLedger(_ ledger: ReadyAlertLedger, serverID: String) {
        guard let data = try? JSONEncoder().encode(ledger) else { return }

        UserDefaults.appSuite.set(data, forKey: ledgerKey(serverID: serverID))
    }
}
