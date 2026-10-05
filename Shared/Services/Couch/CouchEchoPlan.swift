//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

// Note: Foundation-only on purpose, so the rules can be type-checked and tested without the app.

/// Decides what a playback event from the primary user's player echoes to one
/// other member on the couch.
///
/// The rules protect each member's own watch history:
/// - A member who is **ahead** (their own resume point is more than
///   `aheadThresholdTicks` past the playhead) is never rewound: their progress and
///   stop echoes report `max(playhead, their position)` until a progress event
///   passes their position. Their start echo is still sent, so their
///   now-playing session opens and closes normally.
/// - A **re-watcher** (the item is already played for them) gets no start or
///   progress echo, so Jellyfin never marks the item unplayed for them or gives it a
///   resume point. A finished stop only bumps their play count and last played date.
/// - A **failed** stop (the stream errored) is still echoed, so the member's
///   session closes, but never writes user data.
///
/// A member without a snapshot (their user data couldn't be fetched) gets the
/// event as is.
enum CouchEchoPlan {

    enum EventKind {
        case start
        case progress
        case stop
    }

    /// The parts of a playback event that the rules look at.
    struct Event: Equatable {

        var kind: EventKind
        var positionTicks: Int
        var didFinish: Bool
        var isFailed: Bool

        init(
            kind: EventKind,
            positionTicks: Int,
            didFinish: Bool = false,
            isFailed: Bool = false
        ) {
            self.kind = kind
            self.positionTicks = positionTicks
            self.didFinish = didFinish
            self.isFailed = isFailed
        }
    }

    /// A member's own user data for the item, fetched when playback started.
    struct MemberSnapshot: Equatable {

        /// The member's own resume position when playback started.
        var startTicks: Int
        /// Whether the member had already watched the item.
        var isPlayed: Bool
        /// The member's play count when playback started, if known.
        var playCount: Int?
        /// Whether the playhead has passed the member's own position since playback started.
        var hasPassed: Bool

        init(
            startTicks: Int,
            isPlayed: Bool,
            playCount: Int? = nil,
            hasPassed: Bool = false
        ) {
            self.startTicks = startTicks
            self.isPlayed = isPlayed
            self.playCount = playCount
            self.hasPassed = hasPassed
        }
    }

    /// What to do for one member.
    enum Action: Equatable {
        /// Send the playback report with this position.
        case send(Int)
        /// Send nothing.
        case skip
        /// Write only `playCount + 1` and `lastPlayedDate = now`.
        case writeFinishedRewatch
    }

    /// The user data to write directly for a member.
    enum UserDataWrite: Equatable {
        /// Played, position reset, play count bumped.
        case played
        /// A resume point at this position.
        case resume(Int)
        /// Only the play count and last played date (a finished re-watch).
        case finishedRewatch
    }

    /// Why a member's progress couldn't be saved.
    enum FailureKind: Equatable {
        /// 401 or 403: the member's sign-in was revoked or ran out.
        case signInExpired
        /// Anything else: the server or the network had a problem.
        case transient
    }

    /// Ticks per second (Jellyfin ticks are 100 ns).
    static let ticksPerSecond = 10_000_000

    /// A member counts as ahead when their own position is more than this far past the playhead.
    static let aheadThresholdTicks = 60 * ticksPerSecond

    /// Below Jellyfin's default `MinResumePct` of 5% there is no resume point to write.
    static let minResumeFraction = 0.05

    // MARK: - Decisions

    /// What the event echoes to a member.
    ///
    /// - Parameter member: The member's snapshot, or `nil` when it couldn't be fetched.
    static func action(for event: Event, member: MemberSnapshot?) -> Action {
        guard let member else {
            return .send(event.positionTicks)
        }

        if member.isPlayed {
            guard event.kind == .stop, event.didFinish, !event.isFailed else { return .skip }

            return .writeFinishedRewatch
        }

        if isAhead(member, positionTicks: event.positionTicks) {
            return .send(max(event.positionTicks, member.startTicks))
        }

        return .send(event.positionTicks)
    }

    /// Whether the member is ahead of the playhead and must not be rewound.
    static func isAhead(_ member: MemberSnapshot, positionTicks: Int) -> Bool {
        guard !member.isPlayed, !member.hasPassed else { return false }

        return member.startTicks - positionTicks > aheadThresholdTicks
    }

    /// The member's snapshot after the event: a progress or stop event at or past the
    /// member's own position means the couch has caught up with them.
    static func advanced(_ member: MemberSnapshot, by event: Event) -> MemberSnapshot {
        guard event.kind != .start, !member.hasPassed, event.positionTicks >= member.startTicks else { return member }

        var member = member
        member.hasPassed = true
        return member
    }

    /// The user data to write directly for a member, if any.
    ///
    /// - `.writeFinishedRewatch` always writes the re-watch.
    /// - A `.send` stop writes only as a fallback, when the stop report itself failed:
    ///   played for a finished stop, otherwise the resume point if it is past 5%.
    /// - A failed stop never writes anything.
    ///
    /// - Parameters:
    ///   - action: The action from `action(for:member:)`.
    ///   - runtimeTicks: The item's runtime, if known.
    static func userDataWrite(for event: Event, action: Action, runtimeTicks: Int?) -> UserDataWrite? {
        guard event.kind == .stop, !event.isFailed else { return nil }

        switch action {
        case .skip:
            return nil
        case .writeFinishedRewatch:
            return .finishedRewatch
        case let .send(ticks):
            if event.didFinish {
                return .played
            }

            guard let runtimeTicks, runtimeTicks > 0,
                  Double(ticks) / Double(runtimeTicks) >= minResumeFraction
            else { return nil }

            return .resume(ticks)
        }
    }

    /// Classifies a failed request to a member's account.
    ///
    /// - Returns: `nil` for 404, which means the member can't see the item (for example
    ///   parental controls): that is expected and never a failure.
    static func failureKind(statusCode: Int?) -> FailureKind? {
        switch statusCode {
        case 401, 403:
            .signInExpired
        case 404:
            nil
        default:
            .transient
        }
    }
}

// MARK: - Results

/// A member whose progress couldn't be saved.
struct CouchSyncFailure: Equatable {

    let name: String
    let kind: CouchEchoPlan.FailureKind
}

/// The outcome of mirroring a change to every other member on the couch.
///
/// Each list holds member display names, in couch order.
struct CouchSyncResult: Equatable {

    /// Members whose change was saved.
    var synced: [String] = []
    /// Members whose change couldn't be saved.
    var failed: [String] = []
    /// Members who can't see the item (404), so there was nothing to save.
    var notVisible: [String] = []
    /// The members in `failed` whose sign-in ran out (401 or 403).
    var signInExpired: [String] = []

    init(
        synced: [String] = [],
        failed: [String] = [],
        notVisible: [String] = [],
        signInExpired: [String] = []
    ) {
        self.synced = synced
        self.failed = failed
        self.notVisible = notVisible
        self.signInExpired = signInExpired
    }

    /// Whether every member was either synced or can't see the item.
    var isComplete: Bool {
        failed.isEmpty
    }

    mutating func recordSuccess(_ name: String) {
        synced.append(name)
    }

    /// Records a failed request, classified with `CouchEchoPlan.failureKind(statusCode:)`.
    mutating func recordFailure(_ name: String, statusCode: Int?) {
        switch CouchEchoPlan.failureKind(statusCode: statusCode) {
        case nil:
            notVisible.append(name)

        case .signInExpired:
            failed.append(name)
            signInExpired.append(name)

        case .transient:
            failed.append(name)
        }
    }

    /// The failures, for `Notifications[.couchSyncDidFail]`.
    var failures: [CouchSyncFailure] {
        failed.map { name in
            CouchSyncFailure(
                name: name,
                kind: signInExpired.contains(name) ? .signInExpired : .transient
            )
        }
    }
}
