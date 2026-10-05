//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// What this device already told whom, plus its own library sightings, for one Jellyfin server.
///
/// Foundation only: this file is type-checked and unit-tested on Linux.
/// Stored as JSON in the app suite (see `ReadyAlertsService`); never synced. Each device announces on its own,
/// and per user: telling Sam on a shared iPhone doesn't silence Lisa's banner.
struct ReadyAlertLedger: Codable, Equatable {

    struct Announcement: Codable, Equatable {
        var userIDs: Set<String>
        var date: Date
    }

    var createdAt: Date
    /// Arrival id → who was told on this device.
    var announced: [String: Announcement]
    /// Candidate id → first time seen NOT in the library.
    var seenUnavailable: [String: Date]
    /// Candidate id → first time seen in the library after that.
    var firstSeenAvailable: [String: Date]

    init(createdAt: Date) {
        self.createdAt = createdAt
        self.announced = [:]
        self.seenUnavailable = [:]
        self.firstSeenAvailable = [:]
    }

    // MARK: - Announcements

    func isAnnounced(_ arrivalID: String, to userID: String) -> Bool {
        announced[arrivalID]?.userIDs.contains(userID) == true
    }

    /// Adds `userIDs` to the people told about `arrivalID`.
    mutating func markAnnounced(_ arrivalID: String, to userIDs: Set<String>, at date: Date) {
        guard userIDs.isEmpty == false else { return }

        var announcement = announced[arrivalID] ?? Announcement(userIDs: [], date: date)
        announcement.userIDs.formUnion(userIDs)
        announcement.date = max(announcement.date, date)
        announced[arrivalID] = announcement
    }

    /// First-run seeding: marks every arrival older than `ReadyAlertRules.seedSilenceInterval`
    /// as announced to its whole audience, so updating the app doesn't flood anyone.
    mutating func seed(with arrivals: [ReadyArrival], now: Date) {
        for arrival in arrivals where now.timeIntervalSince(arrival.arrivedAt) > ReadyAlertRules.seedSilenceInterval {
            markAnnounced(arrival.id, to: arrival.audience, at: now)
        }
    }

    // MARK: - Sightings

    /// Records whether the candidate is in the library right now.
    ///
    /// `firstSeenAvailable` is only set when the candidate was seen missing before,
    /// so it's evidence that it arrived after it was wished for.
    mutating func recordSighting(_ candidateID: String, isAvailable: Bool, at date: Date) {
        if isAvailable {
            if seenUnavailable[candidateID] != nil, firstSeenAvailable[candidateID] == nil {
                firstSeenAvailable[candidateID] = date
            }
        } else {
            if seenUnavailable[candidateID] == nil {
                seenUnavailable[candidateID] = date
            }
            // Removed from the library again: a later return is a new arrival
            firstSeenAvailable.removeValue(forKey: candidateID)
        }
    }

    // MARK: - Pruning

    /// Drops records older than 60 days.
    mutating func prune(now: Date) {
        prune(now: now, keeping: [])
    }

    /// Drops records older than 60 days, except those of `keptIDs` (arrivals and candidates that still exist,
    /// so a long-awaited title keeps its sighting and an announced arrival isn't announced again).
    mutating func prune(now: Date, keeping keptIDs: Set<String>) {
        let cutoff = now.addingTimeInterval(-ReadyAlertRules.ledgerRetention)

        announced = announced.filter { id, announcement in
            announcement.date >= cutoff || keptIDs.contains(id)
        }
        seenUnavailable = seenUnavailable.filter { id, date in
            date >= cutoff || keptIDs.contains(id)
        }
        firstSeenAvailable = firstSeenAvailable.filter { id, date in
            date >= cutoff || keptIDs.contains(id)
        }
    }
}
