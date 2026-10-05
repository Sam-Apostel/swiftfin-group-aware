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
import UIKit

extension Container {

    var couchVoteParticipant: Factory<CouchVoteParticipant> {
        self { @MainActor in CouchVoteParticipant() }
            .singleton
    }
}

/// The phone side of "Vote for tonight", for the signed-in user.
///
/// While listening (app in the foreground), it reads the user's own poll row every 10 s, and every 2 s while a vote
/// is open. `poll` is the poll to prompt for, or the outcome of a vote this device prompted for (closed or cancelled),
/// else `nil`. Votes go to the user's own ballot row; the host reads them.
@MainActor
final class CouchVoteParticipant: ObservableObject {

    /// A promptable poll, or the outcome of one this device prompted for; else `nil`.
    @Published
    private(set) var poll: CouchVotePoll?
    /// This user's current vote on `poll` (phone ballot or a vote cast for them on the TV, the latest wins).
    @Published
    private(set) var myChoice: CouchVoteChoice?
    @Published
    private(set) var isSending: Bool = false

    private var listenTask: Task<Void, Never>?
    private var isRefreshing = false
    private var sendingCount = 0
    private var ballotWriteChain: Task<Void, Never>?

    /// `serverID|userID` of the account the state below belongs to.
    private var accountKey: String?
    private var latestPoll: CouchVotePoll?
    private var myBallot: CouchVoteBallot?
    private var ballotFetchedPollID: String?

    private var dismissedPollIDs: Set<String> = []
    private var promptedPollIDs: Set<String> = []

    private let logger = Logger.swiftfin()

    init() {}

    // MARK: - Public

    /// Starts polling the user's poll row. Idempotent.
    func startListening() {
        guard listenTask == nil else { return }

        listenTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let delay = await self?.listenTick() else { return }

                try? await Task.sleep(for: delay)
            }
        }
    }

    func stopListening() {
        listenTask?.cancel()
        listenTask = nil
    }

    /// Reads the poll row now (app came to the foreground, prompt opened).
    func refreshNow() async {
        guard !isRefreshing else { return }
        guard let session = Container.shared.currentUserSession() else {
            accountKey = nil
            resetState()
            return
        }

        let userID = session.user.id
        let key = "\(session.server.id)|\(userID)"

        if key != accountKey {
            accountKey = key
            resetState()
        }

        isRefreshing = true
        defer { isRefreshing = false }

        let client = session.client

        do {
            latestPoll = try await CouchVoteService.fetchPoll(userID: userID, client: client)
        } catch {
            if !(error is CancellationError) {
                logger.error("Couch vote: reading the poll failed: \(error.localizedDescription)")
            }
        }

        guard key == accountKey else { return }

        await fetchMyBallotIfNeeded(userID: userID, client: client)

        guard key == accountKey else { return }

        evaluate(userID: userID)
    }

    /// Votes for `optionID` (`nil` = "Anything's fine"). Voting again changes the vote.
    ///
    /// Shown right away; reverted and rethrown when the write fails.
    func vote(optionID: String?) async throws {
        guard let poll, poll.state == .open else {
            throw CouchVoteError.pollNotOpen
        }
        guard let session = Container.shared.currentUserSession(), poll.participantIDs.contains(session.user.id) else {
            throw CouchVoteError.noSession
        }

        if let optionID, poll.option(id: optionID) == nil {
            throw CouchVoteError.pollNotOpen
        }

        let userID = session.user.id
        let client = session.client
        let previousBallot = myBallot
        let previousFetchedPollID = ballotFetchedPollID

        let choice = CouchVoteChoice(
            optionID: optionID,
            votedAt: CouchVoteSync.voteTime(after: myChoice?.votedAt, now: .now)
        )
        let ballot = CouchVoteBallot(pollID: poll.id, userID: userID, choice: choice)

        myBallot = ballot
        myChoice = choice
        ballotFetchedPollID = poll.id

        sendingCount += 1
        isSending = true

        defer {
            sendingCount -= 1
            isSending = sendingCount > 0
        }

        // One write at a time, so a quick change of mind can't land before the first vote
        let previousWrite = ballotWriteChain
        let write = Task { @MainActor () -> Error? in
            await previousWrite?.value

            do {
                try await CouchVoteService.writeBallot(ballot, client: client)
                return nil
            } catch {
                return error
            }
        }

        ballotWriteChain = Task {
            _ = await write.value
        }

        if let error = await write.value {
            logger.error("Couch vote: sending the vote failed: \(error.localizedDescription)")

            // Revert, unless a newer vote replaced this one meanwhile
            if myBallot == ballot {
                myBallot = previousBallot
                // Read the stored ballot again if it hadn't been read yet
                ballotFetchedPollID = previousFetchedPollID
                evaluate(userID: userID)
            }

            throw error
        }
    }

    /// Hides the current poll and never prompts for it again (in this app run).
    func dismiss() {
        guard let poll else { return }

        dismissedPollIDs.insert(poll.id)
        self.poll = nil
        myChoice = nil
    }
}

// MARK: - State

extension CouchVoteParticipant {

    private func listenTick() async -> Duration {
        await refreshNow()

        return poll?.state == .open ? CouchVoteSync.participantActiveInterval : CouchVoteSync.participantIdleInterval
    }

    private func resetState() {
        latestPoll = nil
        myBallot = nil
        ballotFetchedPollID = nil

        if poll != nil {
            poll = nil
        }
        if myChoice != nil {
            myChoice = nil
        }
    }

    /// Reads this user's ballot once per poll, so a vote from before an app restart shows as chosen.
    private func fetchMyBallotIfNeeded(userID: String, client: JellyfinClient) async {
        guard let latestPoll,
              latestPoll.participantIDs.contains(userID),
              ballotFetchedPollID != latestPoll.id
        else { return }

        let pollID = latestPoll.id

        do {
            let ballot = try await CouchVoteService.fetchBallot(userID: userID, client: client)

            // A vote sent meanwhile is newer than what was read
            guard ballotFetchedPollID != pollID else { return }

            myBallot = ballot
            ballotFetchedPollID = pollID
        } catch {
            if !(error is CancellationError) {
                logger.error("Couch vote: reading the own ballot failed: \(error.localizedDescription)")
            }
        }
    }

    private func evaluate(userID: String) {
        let now = Date.now
        var visible: CouchVotePoll?

        if let latestPoll {
            if CouchVoteSync.isPromptable(
                latestPoll,
                userID: userID,
                deviceID: UIDevice.vendorUUIDString,
                dismissedPollIDs: dismissedPollIDs,
                now: now
            ) {
                promptedPollIDs.insert(latestPoll.id)
                visible = latestPoll
            } else if promptedPollIDs.contains(latestPoll.id),
                      !dismissedPollIDs.contains(latestPoll.id),
                      CouchVoteSync.isShowingResult(latestPoll, now: now)
            {
                visible = latestPoll
            }
        }

        if visible != poll {
            poll = visible
        }

        var choice: CouchVoteChoice?
        if let visible {
            choice = CouchVoteSync.choice(of: userID, in: visible, ballot: myBallot)
        }

        if choice != myChoice {
            myChoice = choice
        }
    }
}
