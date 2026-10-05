//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// The rules that decide when a wish "arrived" and who sees it.
///
/// Foundation only: this file is type-checked and unit-tested on Linux.
enum ReadyAlertRules {

    /// Only arrivals from the last 14 days are published.
    static let arrivalWindow: TimeInterval = 14 * 24 * 60 * 60

    /// On the first refresh of a server, arrivals older than this are marked announced silently,
    /// so updating the app doesn't flood anyone.
    static let seedSilenceInterval: TimeInterval = 24 * 60 * 60

    /// Ledger records older than this are pruned.
    static let ledgerRetention: TimeInterval = 60 * 24 * 60 * 60

    /// When a wished-for title arrived in the library.
    ///
    /// - A title arrived when the library added it (`dateCreated`) after it was wished for.
    /// - A series with `usesLastMediaAdded` (a Seerr request newer than the watchlist entry, e.g. a new season)
    ///   also arrived when media was added to it (`dateLastMediaAdded`) after the request.
    /// - Without a `dateCreated`, the device's own sighting counts: `firstSeenAvailable` is only set when this device
    ///   saw the title missing from the library before it saw it there.
    ///
    /// - Returns: `nil` when it was already in the library when wished for (or there is no evidence yet).
    static func arrivalDate(
        isSeries: Bool,
        usesLastMediaAdded: Bool,
        dateCreated: Date?,
        dateLastMediaAdded: Date?,
        wishedAt: Date,
        firstSeenAvailable: Date?
    ) -> Date? {
        if let dateCreated, dateCreated > wishedAt {
            return dateCreated
        }

        if isSeries, usesLastMediaAdded, let dateLastMediaAdded, dateLastMediaAdded > wishedAt {
            return dateLastMediaAdded
        }

        guard dateCreated == nil else { return nil }

        return firstSeenAvailable
    }

    /// Whether an arrival for `audience` is shown to a couch of `memberIDs`.
    ///
    /// - Solo (1 member): the audience contains them.
    /// - Group: every member is in the audience (audience ⊇ members), so a pick for Tuur alone
    ///   isn't shown to the whole couch.
    /// - An empty audience or no members: false.
    static func isVisible(audience: Set<String>, forMembers memberIDs: Set<String>) -> Bool {
        guard audience.isEmpty == false, memberIDs.isEmpty == false else { return false }

        return memberIDs.isSubset(of: audience)
    }

    /// Whether the arrival is within the last `arrivalWindow`. A date in the future (clock skew) counts as recent.
    static func isRecent(_ arrivedAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(arrivedAt) <= arrivalWindow
    }

    /// The arrivals to publish: recent ones only, one per Jellyfin item, newest arrival first.
    ///
    /// When several arrivals point at the same item, the newest one is kept (a watchlist arrival wins a tie)
    /// and its audience becomes the union of all of them.
    static func publishable(_ arrivals: [ReadyArrival], now: Date) -> [ReadyArrival] {
        var byItemID: [String: ReadyArrival] = [:]

        for arrival in arrivals where isRecent(arrival.arrivedAt, now: now) {
            guard let existing = byItemID[arrival.jellyfinItemID] else {
                byItemID[arrival.jellyfinItemID] = arrival
                continue
            }

            let winner = isPreferred(arrival, over: existing) ? arrival : existing

            byItemID[arrival.jellyfinItemID] = ReadyArrival(
                id: winner.id,
                source: winner.source,
                watchlistEntryID: winner.watchlistEntryID ?? existing.watchlistEntryID ?? arrival.watchlistEntryID,
                jellyfinItemID: winner.jellyfinItemID,
                title: winner.title,
                audience: existing.audience.union(arrival.audience),
                wishedAt: winner.wishedAt,
                arrivedAt: winner.arrivedAt
            )
        }

        return byItemID.values.sorted { lhs, rhs in
            if lhs.arrivedAt != rhs.arrivedAt {
                return lhs.arrivedAt > rhs.arrivedAt
            }
            return lhs.id < rhs.id
        }
    }

    private static func isPreferred(_ candidate: ReadyArrival, over existing: ReadyArrival) -> Bool {
        if candidate.arrivedAt != existing.arrivedAt {
            return candidate.arrivedAt > existing.arrivedAt
        }
        if candidate.source != existing.source {
            return candidate.source == .watchlist
        }
        return candidate.id < existing.id
    }
}
