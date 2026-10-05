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

/// Mirrors playback progress and played state to every member on the couch.
///
/// Registered in `UserSession.services`, so it is started and stopped with the
/// primary user session. Couch member sessions are inert and never start it.
///
/// Playback is mirrored by echo reporting: each member's own client (which uses
/// its own device ID) sends its own playback start, progress and stop reports, so
/// the server applies resume points, played state and play counts per member.
/// When a member's report fails, their user data is written directly on stop.
///
/// With a solo couch, everything here is a no-op and makes no network calls.
@MainActor
final class CouchPlaybackService: UserSessionService {

    private let logger = Logger.swiftfin()

    private weak var userSession: UserSession?

    /// The last queued echo. Echoes run one after another so that a member's
    /// start, progress and stop reports reach the server in order.
    private var echoTask: Task<Void, Never>?
    private var isEchoing = false

    /// Members whose playback reports failed for the current item. Their progress
    /// is no longer echoed, and their user data is written directly on stop.
    private var failedMemberIDs: Set<String> = []

    init() {}

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
    /// with each member's own client.
    ///
    /// Call this after the primary user's own change succeeded. Never posts
    /// `itemUserDataDidChange`, so the primary user's displayed state is untouched.
    func mirrorPlayed(itemID: String, isPlayed: Bool) {
        let members = memberSessions
        guard members.isNotEmpty else { return }

        Task {
            var syncedNames: [String] = []

            for member in members {
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

                    syncedNames.append(member.user.username)
                } catch {
                    logger.error(
                        "Couch: failed to mirror played state",
                        metadata: [
                            "itemID": .stringConvertible(itemID),
                            "isPlayed": .stringConvertible(isPlayed),
                            "memberID": .stringConvertible(member.user.id),
                            "error": .stringConvertible(error.localizedDescription),
                        ]
                    )
                }
            }

            logSynced(syncedNames, what: isPlayed ? "played" : "unplayed", itemID: itemID)
        }
    }

    // MARK: - Playback echo

    /// Echoes a playback event from the primary user's player to every other
    /// member on the couch. Fire-and-forget; failures are logged, never surfaced.
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

        if event.kind == .start {
            failedMemberIDs = []
        }

        var syncedNames: [String] = []

        for member in members {
            let memberID = member.user.id

            if event.kind == .progress, failedMemberIDs.contains(memberID) {
                continue
            }

            do {
                try await sendPlaybackReport(event, client: member.client)
                syncedNames.append(member.user.username)
            } catch {
                logger.warning(
                    "Couch: playback report failed for member",
                    metadata: [
                        "kind": .stringConvertible(String(describing: event.kind)),
                        "itemID": .stringConvertible(event.itemID),
                        "memberID": .stringConvertible(memberID),
                        "error": .stringConvertible(error.localizedDescription),
                    ]
                )

                failedMemberIDs.insert(memberID)

                if event.kind == .stop, await writeUserData(for: event, member: member) {
                    syncedNames.append(member.user.username)
                }
            }
        }

        if event.kind == .stop {
            failedMemberIDs = []
            logSynced(syncedNames, what: event.didFinish ? "played" : "progress", itemID: event.itemID)
        }
    }

    private func sendPlaybackReport(_ event: CouchPlaybackEvent, client: JellyfinClient) async throws {
        switch event.kind {
        case .start:
            let info = PlaybackStateInfo(
                canSeek: true,
                isPaused: false,
                itemID: event.itemID,
                positionTicks: event.positionTicks
            )
            try await client.send(Paths.reportPlaybackStart(info))

        case .progress:
            let info = PlaybackStateInfo(
                canSeek: true,
                isPaused: event.isPaused,
                itemID: event.itemID,
                positionTicks: event.positionTicks
            )
            try await client.send(Paths.reportPlaybackProgress(info))

        case .stop:
            let info = PlaybackStopInfo(
                itemID: event.itemID,
                positionTicks: event.positionTicks
            )
            try await client.send(Paths.reportPlaybackStopped(info))
        }
    }

    /// Fallback for a member whose stop report failed: write their resume point,
    /// or their played state, directly. Returns whether the write succeeded.
    private func writeUserData(for event: CouchPlaybackEvent, member: UserSession) async -> Bool {
        let memberID = member.user.id
        var userData = UpdateUserItemDataDto()

        if event.didFinish {
            let current = try? await member.client
                .send(
                    Paths.getItemUserData(itemID: event.itemID, userID: memberID)
                )
                .value

            userData.isPlayed = true
            userData.playbackPositionTicks = 0
            userData.playCount = (current?.playCount ?? 0) + 1
        } else {
            // Below Jellyfin's default `MinResumePct` of 5% there is no resume point to write.
            guard let playedFraction = event.playedFraction, playedFraction >= 0.05 else { return false }

            userData.playbackPositionTicks = event.positionTicks
        }

        userData.lastPlayedDate = .now

        do {
            _ = try await member.client.send(
                Paths.updateItemUserData(itemID: event.itemID, userID: memberID, userData)
            )
            return true
        } catch {
            logger.error(
                "Couch: failed to write member user data",
                metadata: [
                    "itemID": .stringConvertible(event.itemID),
                    "memberID": .stringConvertible(memberID),
                    "error": .stringConvertible(error.localizedDescription),
                ]
            )
            return false
        }
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
