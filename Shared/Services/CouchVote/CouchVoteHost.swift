//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Foundation
import JellyfinAPI
import Logging
import UIKit

/// Runs a "Vote for tonight" on the host device (the TV).
///
/// - `start` writes the poll into the poll row of every couch member this device has a session for.
///   Members without a session (or whose write failed) vote on the host with `castOnHost`.
/// - Every 2 s the host reads the ballot rows of the phone members and updates `tally`.
/// - The vote closes at the deadline, on `closeNow`, or `CouchVoteSync.allVotedSettle` after everyone voted.
///   The winner is written back to every phone member's poll row.
///
/// All poll writes run one at a time in order (start → vote counts → close/cancel), and nothing throws:
/// network failures are logged and degrade to voting on the host.
@MainActor
final class CouchVoteHost: ObservableObject {

    enum Phase: Equatable {
        case idle
        case starting
        case open
        case closed(winnerOptionID: String?)
        case cancelled
    }

    @Published
    private(set) var phase: Phase = .idle
    @Published
    private(set) var poll: CouchVotePoll?
    @Published
    private(set) var tally: CouchVoteTally = .empty
    /// Members whose account received the poll: they can vote on their phone.
    @Published
    private(set) var phoneMemberIDs: Set<String> = []
    /// Members without a session on this device, or whose poll write failed: they vote on the host.
    @Published
    private(set) var hostOnlyMemberIDs: Set<String> = []
    /// Phone members whose ballot couldn't be read `CouchVoteSync.unreachableAfterFailures` times in a row.
    @Published
    private(set) var unreachableMemberIDs: Set<String> = []
    /// Members taking part in another host's vote (their poll row or ballot belongs to it).
    @Published
    private(set) var elsewhereMemberIDs: Set<String> = []

    let couch: CouchGroup

    private let primary: UserSession

    /// Accounts of the phone members (during `.starting`: every member with a session).
    private var accounts: [String: Account] = [:]
    private var ballots: [String: CouchVoteBallot] = [:]
    private var failureCounts: [String: Int] = [:]
    private var elsewhereByBallot: Set<String> = []
    private var elsewhereByPoll: Set<String> = []

    private var loopTask: Task<Void, Never>?
    private var writeChain: Task<Void, Never>?
    /// Bumped by every `start`, so work of an earlier vote never touches a newer one.
    private var generation = 0
    private var isStopped = false
    private var tickCount = 0

    /// The poll as last written to the phones, to know when the vote counts need an update.
    private var lastWrittenPoll: CouchVotePoll?
    private var lastWriteDate: Date?
    /// When everyone had voted (reset by every change), for the settle time before closing.
    private var allVotedSince: Date?

    private let logger = Logger.swiftfin()

    /// Every this many ticks the host also re-reads the poll rows, to notice another host's newer vote.
    private static let pollCheckEveryTicks = 5

    init(couch: CouchGroup, primary: UserSession) {
        self.couch = couch
        self.primary = primary
    }

    // MARK: - Public

    /// Starts a vote between `options` (deduplicated, at most 5). Returns once the poll was sent to the phones.
    func start(options: [CouchVoteOption], duration: TimeInterval = CouchVoteSync.defaultDuration) async {
        guard phase != .starting, phase != .open else { return }

        var uniqueOptions: [CouchVoteOption] = []
        for option in options where !uniqueOptions.contains(where: { $0.id == option.id }) {
            uniqueOptions.append(option)
        }
        uniqueOptions = Array(uniqueOptions.prefix(CouchVoteSync.maxOptions))

        guard !uniqueOptions.isEmpty else {
            logger.error("Couch vote: can't start a vote without options")
            return
        }

        stopLoop()
        generation += 1
        let generation = self.generation
        isStopped = false
        resetState()

        let now = Date.now
        let newPoll = CouchVotePoll(
            couchID: couch.id,
            couchTitle: couch.displayNames,
            hostUserID: primary.user.id,
            hostDeviceID: UIDevice.vendorUUIDString,
            participantIDs: couch.members.map(\.id),
            options: uniqueOptions,
            createdAt: now,
            deadline: now.addingTimeInterval(max(duration, 5)),
            updatedAt: now
        )

        let candidates = makeAccounts()
        accounts = Dictionary(candidates.map { ($0.userID, $0) }) { first, _ in first }
        poll = newPoll
        phase = .starting

        lastWrittenPoll = newPoll
        lastWriteDate = now
        let failedUserIDs = await enqueueWrite(newPoll, to: candidates).value

        guard generation == self.generation else { return }

        let delivered = candidates.filter { !failedUserIDs.contains($0.userID) }
        accounts = Dictionary(delivered.map { ($0.userID, $0) }) { first, _ in first }
        phoneMemberIDs = Set(accounts.keys)
        hostOnlyMemberIDs = Set(newPoll.participantIDs).subtracting(phoneMemberIDs)

        if delivered.isEmpty {
            logger.warning("Couch vote: no phone account could be reached, voting on this device only")
        }

        // Cancelled or stopped while sending
        guard phase == .starting, !isStopped else { return }

        phase = .open
        recomputeTally()
        startLoop()
    }

    /// Records a vote cast on the host for `userID` (`nil` = "Anything's fine").
    ///
    /// Also works for phone members, as an override: it's always later than their phone vote.
    func castOnHost(userID: String, optionID: String?) {
        guard phase == .open || phase == .starting, var poll, poll.participantIDs.contains(userID) else { return }

        if let optionID, poll.option(id: optionID) == nil {
            logger.error("Couch vote: ignoring a vote for an unknown option")
            return
        }

        let previous = CouchVoteSync.choice(of: userID, in: poll, ballot: ballots[userID])
        poll.hostVotes[userID] = CouchVoteChoice(
            optionID: optionID,
            votedAt: CouchVoteSync.voteTime(after: previous?.votedAt, now: .now)
        )
        self.poll = poll

        recomputeTally()
        publishVoteCountsIfNeeded()
    }

    /// Closes the vote now (after one last read of the ballots) and publishes the winner.
    func closeNow() async {
        guard phase == .open else { return }

        await refreshBallots(checkPollRows: false)
        await close()
    }

    /// Cancels the vote; the phones dismiss their prompt.
    func cancel() async {
        guard phase == .open || phase == .starting, var poll else { return }

        stopLoop()

        let now = Date.now
        poll.state = .cancelled
        poll.closedAt = now
        poll.updatedAt = now
        self.poll = poll
        phase = .cancelled

        _ = await enqueueWrite(poll, to: writableAccounts).value
    }

    /// Stops polling without writing anything (the view is gone). Idempotent.
    ///
    /// Writes already in flight (close, cancel) still finish.
    func stop() {
        isStopped = true
        stopLoop()
    }
}

// MARK: - Loop

extension CouchVoteHost {

    private func startLoop() {
        loopTask?.cancel()

        let generation = self.generation

        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let delay = await self?.tick(generation: generation) else { return }

                try? await Task.sleep(for: delay)
            }
        }
    }

    private func stopLoop() {
        loopTask?.cancel()
        loopTask = nil
    }

    /// One round: read the ballots, update the tally, maybe publish or close.
    /// - Returns: how long to wait for the next round, `nil` to end the loop.
    private func tick(generation: Int) async -> Duration? {
        guard isCurrent(generation) else { return nil }

        tickCount += 1
        await refreshBallots(checkPollRows: tickCount % Self.pollCheckEveryTicks == 0)

        guard isCurrent(generation) else { return nil }

        recomputeTally()
        publishVoteCountsIfNeeded()

        let now = Date.now
        let closeDate = nextCloseDate()

        if let closeDate, now >= closeDate {
            await close()
            return nil
        }

        var delay: TimeInterval = 2
        if let closeDate {
            delay = min(delay, max(closeDate.timeIntervalSince(now), 0.2))
        }
        return .milliseconds(Int(delay * 1000))
    }

    private func isCurrent(_ generation: Int) -> Bool {
        generation == self.generation && phase == .open && !isStopped && !Task.isCancelled
    }

    /// The deadline, or the end of the settle time once everyone voted, whichever is first.
    private func nextCloseDate() -> Date? {
        guard let poll else { return nil }

        var date = poll.deadline
        if let allVotedSince {
            date = min(date, allVotedSince.addingTimeInterval(CouchVoteSync.allVotedSettle))
        }
        return date
    }

    private func close() async {
        guard phase == .open, var poll else { return }

        stopLoop()
        recomputeTally()

        let now = Date.now
        let winner = CouchVoteSync.winner(of: poll, tally: tally)

        poll.state = .closed
        poll.winnerOptionID = winner
        poll.closedAt = now
        poll.updatedAt = now
        poll.votedUserIDs = CouchVoteSync.orderedVotedUserIDs(poll, tally: tally)
        self.poll = poll
        phase = .closed(winnerOptionID: winner)

        _ = await enqueueWrite(poll, to: writableAccounts).value
    }
}

// MARK: - State

extension CouchVoteHost {

    private func resetState() {
        poll = nil
        tally = .empty
        phoneMemberIDs = []
        hostOnlyMemberIDs = []
        unreachableMemberIDs = []
        elsewhereMemberIDs = []
        accounts = [:]
        ballots = [:]
        failureCounts = [:]
        elsewhereByBallot = []
        elsewhereByPoll = []
        tickCount = 0
        lastWrittenPoll = nil
        lastWriteDate = nil
        allVotedSince = nil
    }

    private func recomputeTally() {
        guard let poll else { return }

        let newTally = CouchVoteSync.tally(poll, ballots: ballots)
        let changed = newTally != tally

        if changed {
            tally = newTally
        }

        if CouchVoteSync.everyoneVoted(poll, tally: newTally) {
            if changed || allVotedSince == nil {
                allVotedSince = .now
            }
        } else {
            allVotedSince = nil
        }
    }

    /// Writes the poll with the new `votedUserIDs` (and host votes) to the phones, at most every 3 s.
    /// A throttled update is sent by a later tick.
    private func publishVoteCountsIfNeeded() {
        guard phase == .open, var poll else { return }

        poll.votedUserIDs = CouchVoteSync.orderedVotedUserIDs(poll, tally: tally)

        guard poll.votedUserIDs != lastWrittenPoll?.votedUserIDs || poll.hostVotes != lastWrittenPoll?.hostVotes else { return }

        let now = Date.now
        if let lastWriteDate, now.timeIntervalSince(lastWriteDate) < CouchVoteSync.votedUpdateThrottle {
            return
        }

        poll.updatedAt = now
        self.poll = poll
        lastWrittenPoll = poll
        lastWriteDate = now

        enqueueWrite(poll, to: writableAccounts)
    }

    private func updateElsewhere() {
        let elsewhere = elsewhereByBallot.union(elsewhereByPoll)
        if elsewhere != elsewhereMemberIDs {
            elsewhereMemberIDs = elsewhere
        }
    }
}

// MARK: - Sync

extension CouchVoteHost {

    /// What a network call needs from a member session, safe to pass to child tasks.
    struct Account: Sendable {
        let userID: String
        let client: JellyfinClient
    }

    private struct BallotRead: Sendable {
        let userID: String
        let ballot: CouchVoteBallot?
        let error: String?
    }

    private struct PollRead: Sendable {
        let userID: String
        let poll: CouchVotePoll?
        let didFail: Bool
    }

    private struct WriteFailure: Sendable {
        let userID: String
        let error: String
    }

    /// An account for every couch member this device has a session for (the primary user included).
    private func makeAccounts() -> [Account] {
        var result: [Account] = []

        for member in couch.members {
            guard let session = primary.session(forMemberID: member.id) else { continue }

            result.append(Account(userID: member.id, client: session.client))
        }

        return result
    }

    /// Phone members whose poll row we may write: not those that joined another host's newer vote.
    private var writableAccounts: [Account] {
        accounts.values
            .filter { !elsewhereMemberIDs.contains($0.userID) }
            .sorted { $0.userID < $1.userID }
    }

    /// Queues a poll write after every earlier one.
    /// - Returns: a task with the user ids whose write failed.
    @discardableResult
    private func enqueueWrite(_ poll: CouchVotePoll, to accounts: [Account]) -> Task<Set<String>, Never> {
        let previous = writeChain
        let logger = self.logger

        let task = Task { @MainActor () -> Set<String> in
            await previous?.value

            guard !accounts.isEmpty else { return [] }

            let failures = await Self.writeAll(poll, accounts: accounts)

            for failure in failures {
                logger.error("Couch vote: writing the poll for user \(failure.userID) failed: \(failure.error)")
            }

            return Set(failures.map(\.userID))
        }

        writeChain = Task {
            _ = await task.value
        }

        return task
    }

    /// Reads the ballot rows of the phone members (and every few ticks their poll rows).
    private func refreshBallots(checkPollRows: Bool) async {
        guard let poll else { return }

        let accounts = Array(self.accounts.values)

        guard !accounts.isEmpty else { return }

        let generation = self.generation
        let ballotReads = await Self.fetchBallots(accounts)
        let pollReads = checkPollRows ? await Self.fetchPolls(accounts) : []

        guard generation == self.generation else { return }

        applyBallotReads(ballotReads, poll: poll)
        applyPollReads(pollReads, poll: poll)
        updateElsewhere()
    }

    private func applyBallotReads(_ reads: [BallotRead], poll: CouchVotePoll) {
        var unreachable = unreachableMemberIDs

        for read in reads {
            if let error = read.error {
                let failures = (failureCounts[read.userID] ?? 0) + 1
                failureCounts[read.userID] = failures

                if failures == 1 || failures == CouchVoteSync.unreachableAfterFailures {
                    logger.error("Couch vote: reading the ballot of user \(read.userID) failed (\(failures)x): \(error)")
                }
                if failures >= CouchVoteSync.unreachableAfterFailures {
                    unreachable.insert(read.userID)
                }
                continue
            }

            failureCounts[read.userID] = 0
            unreachable.remove(read.userID)
            ballots[read.userID] = read.ballot

            // A ballot for another poll, cast after ours started: they're voting on another host
            if let ballot = read.ballot, ballot.pollID != poll.id, ballot.choice.votedAt > poll.createdAt {
                elsewhereByBallot.insert(read.userID)
            } else {
                elsewhereByBallot.remove(read.userID)
            }
        }

        if unreachable != unreachableMemberIDs {
            unreachableMemberIDs = unreachable
        }
    }

    /// A newer poll of another host in a member's row wins (the phone shows the newest one): stop writing there.
    /// An older or missing one was overwritten by a slow write of someone else: write ours again.
    private func applyPollReads(_ reads: [PollRead], poll: CouchVotePoll) {
        var rewrite: [Account] = []

        for read in reads where !read.didFail {
            guard let stored = read.poll, stored.id == poll.id else {
                if let stored = read.poll, stored.createdAt > poll.createdAt {
                    elsewhereByPoll.insert(read.userID)
                } else if let account = accounts[read.userID] {
                    elsewhereByPoll.remove(read.userID)
                    rewrite.append(account)
                }
                continue
            }

            elsewhereByPoll.remove(read.userID)
        }

        if !rewrite.isEmpty, phase == .open, let current = self.poll {
            enqueueWrite(current, to: rewrite)
        }
    }

    // MARK: Network (nonisolated, runs in parallel)

    private nonisolated static func writeAll(_ poll: CouchVotePoll, accounts: [Account]) async -> [WriteFailure] {
        await withTaskGroup(of: WriteFailure?.self) { group in
            for account in accounts {
                group.addTask {
                    do {
                        try await CouchVoteService.writePoll(poll, userID: account.userID, client: account.client)
                        return nil
                    } catch {
                        return WriteFailure(userID: account.userID, error: error.localizedDescription)
                    }
                }
            }

            var failures: [WriteFailure] = []
            for await failure in group {
                if let failure {
                    failures.append(failure)
                }
            }
            return failures
        }
    }

    private nonisolated static func fetchBallots(_ accounts: [Account]) async -> [BallotRead] {
        await withTaskGroup(of: BallotRead.self) { group in
            for account in accounts {
                group.addTask {
                    do {
                        let ballot = try await CouchVoteService.fetchBallot(userID: account.userID, client: account.client)
                        return BallotRead(userID: account.userID, ballot: ballot, error: nil)
                    } catch {
                        return BallotRead(userID: account.userID, ballot: nil, error: error.localizedDescription)
                    }
                }
            }

            var reads: [BallotRead] = []
            for await read in group {
                reads.append(read)
            }
            return reads
        }
    }

    private nonisolated static func fetchPolls(_ accounts: [Account]) async -> [PollRead] {
        await withTaskGroup(of: PollRead.self) { group in
            for account in accounts {
                group.addTask {
                    do {
                        let poll = try await CouchVoteService.fetchPoll(userID: account.userID, client: account.client)
                        return PollRead(userID: account.userID, poll: poll, didFail: false)
                    } catch {
                        return PollRead(userID: account.userID, poll: nil, didFail: true)
                    }
                }
            }

            var reads: [PollRead] = []
            for await read in group {
                reads.append(read)
            }
            return reads
        }
    }
}
