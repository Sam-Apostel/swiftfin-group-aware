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
import Get
import JellyfinAPI
import Logging

/// Mirrors playback progress and played state to every member on the couch.
///
/// Registered in `UserSession.services`, so it is started and stopped with the
/// primary user session. Couch member sessions are inert and never start it.
///
/// Playback is mirrored by echo reporting: each member's own client (which uses
/// its own device ID) sends its own playback start, progress and stop reports, so
/// the server applies resume points, played state and play counts per member.
/// When a member's stop report fails, their user data is written directly.
///
/// What each member receives is decided by `CouchEchoPlan`, from their own user
/// data fetched when playback starts: a member who is ahead is never rewound, a
/// member who already watched the item is never marked unwatched, and a failed
/// stream never writes anyone's progress. When a member's progress couldn't be
/// saved at all, `Notifications[.couchSyncDidFail]` is posted.
///
/// With a solo couch, everything here is a no-op and makes no network calls.
@MainActor
final class CouchPlaybackService: UserSessionService {

    private typealias Snapshot = CouchEchoPlan.MemberSnapshot

    /// A member and what to echo to them for one event.
    private struct EchoJob {
        let member: UserSession
        let action: CouchEchoPlan.Action
        let snapshot: Snapshot?
    }

    /// What happened for one member.
    private struct EchoOutcome {
        let memberID: String
        let name: String
        /// Whether the report, or the direct user data write, succeeded.
        var didSync = false
        /// Whether the playback report itself failed.
        var didReportFail = false
        /// The error of a user data write that was needed and failed.
        var saveError: Error?
    }

    private let logger = Logger.swiftfin()

    private weak var userSession: UserSession?

    /// The last queued echo. Echoes run one after another so that a member's
    /// start, progress and stop reports reach the server in order.
    private var echoTask: Task<Void, Never>?
    private var isEchoing = false

    /// Members whose playback reports failed for the current item. Their progress
    /// is no longer echoed, and their user data is written directly on stop.
    private var failedMemberIDs: Set<String> = []

    /// Each member's own user data for the playing item, fetched on start.
    /// Keyed by item ID, then by member ID.
    private var snapshots: [String: [String: CouchEchoPlan.MemberSnapshot]] = [:]

    init() {
        // The listener must exist before the first failed save is posted.
        _ = Container.shared.couchSyncFeedback()
    }

    // MARK: - UserSessionService

    func willStart(userSession: UserSession) async {
        self.userSession = userSession
    }

    func didStart(userSession: UserSession) {
        self.userSession = userSession
    }

    // MARK: - Members

    /// The member sessions to mirror to: empty unless more than one person is on the couch.
    private var memberSessions: [UserSession] {
        guard let userSession = userSession ?? Container.shared.currentUserSession(),
              userSession.couch.isGroup
        else { return [] }

        return userSession.memberSessions
    }

    // MARK: - Played state

    /// Marks the item played or unplayed for every other member on the couch,
    /// with each member's own client. Fire-and-forget: see `mirrorPlayedResult(itemID:isPlayed:)`.
    ///
    /// Call this after the primary user's own change succeeded. Never posts
    /// `itemUserDataDidChange`, so the primary user's displayed state is untouched.
    func mirrorPlayed(itemID: String, isPlayed: Bool) {
        guard memberSessions.isNotEmpty else { return }

        Task {
            _ = await mirrorPlayedResult(itemID: itemID, isPlayed: isPlayed)
        }
    }

    /// Marks the item played or unplayed for every other member on the couch,
    /// concurrently, with each member's own client.
    ///
    /// Call this after the primary user's own change succeeded. Never posts
    /// `itemUserDataDidChange`, so the primary user's displayed state is untouched.
    ///
    /// - Returns: Who was synced, who failed, and who can't see the item (404).
    ///   Empty when the couch is a single person.
    func mirrorPlayedResult(itemID: String, isPlayed: Bool) async -> CouchSyncResult {
        let members = memberSessions
        guard members.isNotEmpty else { return CouchSyncResult() }

        let errors: [Error?] = await concurrently(members) { (member: UserSession) async -> Error? in
            do {
                if isPlayed {
                    _ = try await member.client.send(
                        Paths.markPlayedItem(itemID: itemID, userID: member.user.id)
                    )
                } else {
                    _ = try await member.client.send(
                        Paths.markUnplayedItem(itemID: itemID, userID: member.user.id)
                    )
                }

                return nil
            } catch {
                return error
            }
        }

        var result = CouchSyncResult()

        for (member, error) in zip(members, errors) {
            if let error {
                logger.error(
                    "Couch: failed to mirror played state",
                    metadata: [
                        "itemID": .stringConvertible(itemID),
                        "isPlayed": .stringConvertible(isPlayed),
                        "memberID": .stringConvertible(member.user.id),
                        "error": .stringConvertible(error.localizedDescription),
                    ]
                )

                result.recordFailure(member.user.username, statusCode: Self.statusCode(of: error))
            } else {
                result.recordSuccess(member.user.username)
            }
        }

        logSynced(result.synced, what: isPlayed ? "played" : "unplayed", itemID: itemID)

        return result
    }

    // MARK: - Playback echo

    /// Echoes a playback event from the primary user's player to every other
    /// member on the couch. Fire-and-forget: failures are logged, and a stop whose
    /// progress couldn't be saved for someone posts `couchSyncDidFail`.
    func report(_ event: CouchPlaybackEvent) {

        #if DEBUG
        guard Defaults[.sendProgressReports] else { return }

        #endif

        let members = memberSessions
        guard members.isNotEmpty else { return }

        // Progress is periodic: drop it rather than queue it behind a slow request.
        if event.kind == .progress, isEchoing {
            return
        }

        let previousTask = echoTask

        echoTask = Task {
            await previousTask?.value

            isEchoing = true
            await echo(event, to: members)
            isEchoing = false
        }
    }

    private func echo(_ event: CouchPlaybackEvent, to members: [UserSession]) async {
        let planEvent = event.planEvent

        if event.kind == .start {
            failedMemberIDs = []

            // One item plays at a time: forget every other item's snapshots.
            let fetched = await fetchSnapshots(itemID: event.itemID, members: members)
            snapshots = [event.itemID: fetched]
        }

        var itemSnapshots = snapshots[event.itemID] ?? [:]
        var jobs: [EchoJob] = []

        for member in members {
            let memberID = member.user.id

            if event.kind == .progress, failedMemberIDs.contains(memberID) {
                continue
            }

            let snapshot = itemSnapshots[memberID]
            let action = CouchEchoPlan.action(for: planEvent, member: snapshot)

            if let snapshot {
                itemSnapshots[memberID] = CouchEchoPlan.advanced(snapshot, by: planEvent)
            }

            jobs.append(EchoJob(member: member, action: action, snapshot: snapshot))
        }

        if event.kind == .stop {
            snapshots[event.itemID] = nil
        } else {
            snapshots[event.itemID] = itemSnapshots
        }

        let outcomes: [EchoOutcome] = await concurrently(jobs) { (job: EchoJob) async -> EchoOutcome in
            await self.run(job, for: event)
        }

        for outcome in outcomes where outcome.didReportFail {
            failedMemberIDs.insert(outcome.memberID)
        }

        guard event.kind == .stop else { return }

        failedMemberIDs = []

        logSynced(
            outcomes.filter(\.didSync).map(\.name),
            what: event.didFinish ? "played" : "progress",
            itemID: event.itemID
        )

        reportFailures(outcomes, event: event)
    }

    /// Sends one member's report and, at stop, writes their user data directly when needed.
    private func run(_ job: EchoJob, for event: CouchPlaybackEvent) async -> EchoOutcome {
        let member = job.member
        var outcome = EchoOutcome(memberID: member.user.id, name: member.user.username)

        switch job.action {
        case .skip:
            return outcome
        case .writeFinishedRewatch:
            break
        case let .send(positionTicks):
            do {
                try await sendPlaybackReport(event, positionTicks: positionTicks, client: member.client)
                outcome.didSync = true
                return outcome
            } catch {
                logger.warning(
                    "Couch: playback report failed for member",
                    metadata: [
                        "kind": .stringConvertible(String(describing: event.kind)),
                        "itemID": .stringConvertible(event.itemID),
                        "memberID": .stringConvertible(member.user.id),
                        "error": .stringConvertible(error.localizedDescription),
                    ]
                )

                outcome.didReportFail = true
            }
        }

        guard let write = CouchEchoPlan.userDataWrite(
            for: event.planEvent,
            action: job.action,
            runtimeTicks: event.runtimeTicks
        ) else { return outcome }

        do {
            try await writeUserData(write, itemID: event.itemID, snapshot: job.snapshot, member: member)
            outcome.didSync = true
        } catch {
            outcome.saveError = error
        }

        return outcome
    }

    /// Fetches every member's own user data for the item, concurrently.
    ///
    /// A member whose fetch failed has no snapshot, and gets every event as is.
    private func fetchSnapshots(
        itemID: String,
        members: [UserSession]
    ) async -> [String: CouchEchoPlan.MemberSnapshot] {
        let fetched: [Snapshot?] = await concurrently(members) { (member: UserSession) async -> Snapshot? in
            do {
                let userData = try await member.client
                    .send(
                        Paths.getItemUserData(itemID: itemID, userID: member.user.id)
                    )
                    .value

                return CouchEchoPlan.MemberSnapshot(
                    startTicks: userData.playbackPositionTicks ?? 0,
                    isPlayed: userData.isPlayed ?? false,
                    playCount: userData.playCount
                )
            } catch {
                self.logger.warning(
                    "Couch: couldn't fetch member user data, echoing as is",
                    metadata: [
                        "itemID": .stringConvertible(itemID),
                        "memberID": .stringConvertible(member.user.id),
                        "error": .stringConvertible(error.localizedDescription),
                    ]
                )

                return nil
            }
        }

        var snapshots: [String: CouchEchoPlan.MemberSnapshot] = [:]

        for (member, snapshot) in zip(members, fetched) {
            if let snapshot {
                snapshots[member.user.id] = snapshot
            }
        }

        return snapshots
    }

    private func sendPlaybackReport(
        _ event: CouchPlaybackEvent,
        positionTicks: Int,
        client: JellyfinClient
    ) async throws {
        switch event.kind {
        case .start:
            let info = PlaybackStateInfo(
                canSeek: true,
                isPaused: false,
                itemID: event.itemID,
                positionTicks: positionTicks
            )
            try await client.send(Paths.reportPlaybackStart(info))

        case .progress:
            let info = PlaybackStateInfo(
                canSeek: true,
                isPaused: event.isPaused,
                itemID: event.itemID,
                positionTicks: positionTicks
            )
            try await client.send(Paths.reportPlaybackProgress(info))

        case .stop:
            // Jellyfin closes a failed session without touching the member's user data.
            let info = PlaybackStopInfo(
                isFailed: event.isFailed,
                itemID: event.itemID,
                positionTicks: positionTicks
            )
            try await client.send(Paths.reportPlaybackStopped(info))
        }
    }

    /// Writes a member's user data directly: as a fallback when their stop report
    /// failed, or for a finished re-watch.
    private func writeUserData(
        _ write: CouchEchoPlan.UserDataWrite,
        itemID: String,
        snapshot: CouchEchoPlan.MemberSnapshot?,
        member: UserSession
    ) async throws {
        let memberID = member.user.id
        var userData = UpdateUserItemDataDto()

        switch write {
        case .played, .finishedRewatch:
            let current = try? await member.client
                .send(
                    Paths.getItemUserData(itemID: itemID, userID: memberID)
                )
                .value

            userData.playCount = (current?.playCount ?? snapshot?.playCount ?? 0) + 1

            if write == .played {
                userData.isPlayed = true
                userData.playbackPositionTicks = 0
            }

        case let .resume(positionTicks):
            userData.playbackPositionTicks = positionTicks
        }

        userData.lastPlayedDate = .now

        do {
            _ = try await member.client.send(
                Paths.updateItemUserData(itemID: itemID, userID: memberID, userData)
            )
        } catch {
            logger.error(
                "Couch: failed to write member user data",
                metadata: [
                    "itemID": .stringConvertible(itemID),
                    "memberID": .stringConvertible(memberID),
                    "error": .stringConvertible(error.localizedDescription),
                ]
            )

            throw error
        }
    }

    /// Posts `couchSyncDidFail` for the members whose progress couldn't be saved.
    ///
    /// Members who can't see the item (404) are not failures.
    private func reportFailures(_ outcomes: [EchoOutcome], event: CouchPlaybackEvent) {
        var result = CouchSyncResult()

        for outcome in outcomes {
            guard let saveError = outcome.saveError else { continue }

            result.recordFailure(outcome.name, statusCode: Self.statusCode(of: saveError))
        }

        let failures = result.failures
        guard failures.isNotEmpty else { return }

        logger.error(
            "Couch: couldn't save progress for \(ListFormatter.localizedString(byJoining: result.failed))",
            metadata: [
                "itemID": .stringConvertible(event.itemID),
            ]
        )

        Notifications[.couchSyncDidFail].post(failures)
    }

    // MARK: - Helpers

    /// Runs `body` for every input concurrently, on the main actor (each body
    /// suspends on its network requests), and returns the results in input order.
    private func concurrently<Input, Output: Sendable>(
        _ inputs: [Input],
        _ body: @escaping @MainActor (Input) async -> Output
    ) async -> [Output] {
        await withTaskGroup(of: (Int, Output).self) { group in
            for (index, input) in inputs.enumerated() {
                group.addTask { @MainActor in
                    let output = await body(input)
                    return (index, output)
                }
            }

            var indexed: [(Int, Output)] = []

            for await result in group {
                indexed.append(result)
            }

            return indexed
                .sorted { $0.0 < $1.0 }
                .map(\.1)
        }
    }

    /// The HTTP status code of a failed request, if the server answered.
    private static func statusCode(of error: Error) -> Int? {
        guard case let .unacceptableStatusCode(statusCode)? = error as? Get.APIError else { return nil }

        return statusCode
    }

    private func logSynced(_ names: [String], what: String, itemID: String) {
        guard names.isNotEmpty else { return }

        logger.info(
            "Couch: synced \(what) to \(ListFormatter.localizedString(byJoining: names))",
            metadata: [
                "itemID": .stringConvertible(itemID),
            ]
        )
    }
}
