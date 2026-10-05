//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Defaults
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

/// An account this phone can vote as in the current poll.
struct CouchVoteVoter: Identifiable, Hashable {

    let user: UserState
    let server: ServerState
    /// A kid flag or a server age limit: never the default voter.
    let isRestricted: Bool

    var id: String {
        user.id
    }
}

/// The phone side of "Vote for tonight".
///
/// It listens for **every stored grown-up with a stored token** (`storedAccessToken`, not `isChildAudience`),
/// with inert clients built from the stored users, so it also works on the signed-out couch picker.
/// While listening (app in the foreground), it reads those accounts' poll rows in parallel every 10 s,
/// and every 2 s while a vote is open.
///
/// - `poll` is the poll to prompt for, or the outcome of a vote this device prompted for (closed or cancelled), else `nil`.
/// - `voters` are the accounts on this phone that take part in it; a tap votes as `votingAsUserID`,
///   into **that person's** ballot row, with their own client (one writer per row).
/// - The first time a phone finds a poll promptable for an account, it writes that account's presence row,
///   so the TV knows they are really on a phone.
@MainActor
final class CouchVoteParticipant: ObservableObject {

    /// A promptable poll, or the outcome of one this device prompted for; else `nil`.
    @Published
    private(set) var poll: CouchVotePoll?
    /// The accounts on this phone that can vote in `poll`, in the poll's participant order.
    @Published
    private(set) var voters: [CouchVoteVoter] = []
    /// Who the next tap votes for: one of `voters`.
    @Published
    private(set) var votingAsUserID: String?
    /// The current vote of `votingAsUserID` on `poll` (phone ballot or a vote cast for them on the TV, the latest wins).
    @Published
    private(set) var myChoice: CouchVoteChoice?
    /// The `voters` who already have a vote on `poll`.
    @Published
    private(set) var votedVoterIDs: Set<String> = []
    @Published
    private(set) var isSending: Bool = false

    /// A listened account: an inert member session built from a stored user and its keychain token.
    private struct Account {
        let user: UserState
        let server: ServerState
        let session: UserSession
        let isRestricted: Bool
    }

    /// What a network call needs, safe to pass to child tasks.
    private struct Target: Sendable {
        let userID: String
        let client: JellyfinClient
    }

    private struct PollRead: Sendable {
        let userID: String
        let poll: CouchVotePoll?
        let error: String?
    }

    private struct BallotRead: Sendable {
        let userID: String
        let pollID: String
        let ballot: CouchVoteBallot?
        let error: String?
    }

    private var listenTask: Task<Void, Never>?
    /// Views that want the participant to listen (the signed-in tabs, the signed-out picker).
    private var listenerOwners: Set<String> = []
    private var isRefreshing = false
    private var sendingCount = 0
    private var ballotWriteChain: Task<Void, Never>?

    /// Listened accounts by user id.
    private var accounts: [String: Account] = [:]
    /// Inert sessions by `serverID|url|userID|token`, so clients are reused between reads.
    private var sessionCache: [String: UserSession] = [:]
    /// Accounts whose last poll read failed, so a dead token is logged once and not every 10 s.
    private var failingUserIDs: Set<String> = []

    /// The last poll read from each account's own poll row.
    private var latestPolls: [String: CouchVotePoll] = [:]
    /// Each voter's own ballot (as read, or as last sent from this phone).
    private var ballots: [String: CouchVoteBallot] = [:]
    /// User id → the poll whose ballot was read (or sent) for that user.
    private var ballotFetchedPollIDs: [String: String] = [:]
    /// `pollID|userID` of the presence rows written (or being written).
    private var presenceSentKeys: Set<String> = []

    /// The poll `votingAsUserID` was chosen for: a new poll starts from the default voter again.
    private var votingAsPollID: String?
    /// The last poll this device prompted for, to keep showing its outcome.
    private var shownPollID: String?
    private var dismissedPollIDs: Set<String> = []
    private var promptedPollIDs: Set<String> = []

    private let logger = Logger.swiftfin()

    init() {}

    // MARK: - Public

    /// Starts polling the listened accounts' poll rows. Idempotent per `owner`.
    ///
    /// Several views may listen at once (the signed-out picker and the tabs swap places on sign-in):
    /// polling stops only once every owner stopped.
    func startListening(owner: String = "default") {
        listenerOwners.insert(owner)

        guard listenTask == nil else { return }

        listenTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let delay = await self?.listenTick() else { return }

                try? await Task.sleep(for: delay)
            }
        }
    }

    func stopListening(owner: String = "default") {
        listenerOwners.remove(owner)

        guard listenerOwners.isEmpty else { return }

        listenTask?.cancel()
        listenTask = nil
    }

    /// Reads the poll rows now (app came to the foreground, prompt opened).
    ///
    /// Works without a current session: the accounts come from the stored users.
    func refreshNow() async {
        guard !isRefreshing else { return }

        isRefreshing = true
        defer { isRefreshing = false }

        reloadAccounts()

        guard accounts.isNotEmpty else {
            evaluate()
            return
        }

        let reads = await Self.fetchPolls(targets(for: Array(accounts.keys)))
        applyPollReads(reads)

        await fetchBallotsIfNeeded()

        evaluate()
        sendPresenceIfNeeded()
    }

    /// Votes as `voterID` (default: `votingAsUserID`) for `optionID` (`nil` = "Anything's fine").
    /// Voting again changes the vote.
    ///
    /// Shown right away; reverted and rethrown when the write fails.
    func vote(optionID: String?, as voterID: String? = nil) async throws {
        guard let poll, poll.state == .open else {
            throw CouchVoteError.pollNotOpen
        }
        guard let userID = voterID ?? votingAsUserID,
              let account = accounts[userID],
              poll.participantIDs.contains(userID)
        else {
            throw CouchVoteError.noSession
        }

        if let optionID, poll.option(id: optionID) == nil {
            throw CouchVoteError.pollNotOpen
        }

        let client = account.session.client
        let previousBallot = ballots[userID]
        let previousFetchedPollID = ballotFetchedPollIDs[userID]
        let previousChoice = CouchVoteSync.choice(of: userID, in: poll, ballot: previousBallot)

        let choice = CouchVoteChoice(
            optionID: optionID,
            votedAt: CouchVoteSync.voteTime(after: previousChoice?.votedAt, now: .now)
        )
        let ballot = CouchVoteBallot(pollID: poll.id, userID: userID, choice: choice)

        ballots[userID] = ballot
        ballotFetchedPollIDs[userID] = poll.id
        evaluate()

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
            logger.error("Couch vote: sending the vote of user \(userID) failed: \(error.localizedDescription)")

            // Revert, unless a newer vote replaced this one meanwhile
            if ballots[userID] == ballot {
                ballots[userID] = previousBallot
                // Read the stored ballot again if it hadn't been read yet
                ballotFetchedPollIDs[userID] = previousFetchedPollID
                evaluate()
            }

            throw error
        }
    }

    /// Makes the next tap vote as `userID` (one of `voters`).
    func selectVoter(userID: String) {
        guard voters.contains(where: { $0.id == userID }) else { return }

        votingAsUserID = userID
        votingAsPollID = poll?.id
        evaluate()
    }

    /// The inert session of a voter on this phone (for posters), `nil` when it isn't listened for.
    func session(forVoterID userID: String) -> UserSession? {
        accounts[userID]?.session
    }

    /// Hides the current poll and never prompts for it again (in this app run).
    func dismiss() {
        guard let poll else { return }

        dismissedPollIDs.insert(poll.id)
        self.poll = nil
        myChoice = nil
    }
}

// MARK: - Accounts

extension CouchVoteParticipant {

    /// Every stored user with a stored token who isn't a child, on a known server.
    private func reloadAccounts() {
        let servers = StoredValues[.Server.servers]
        var newAccounts: [String: Account] = [:]
        var usedCacheKeys: Set<String> = []

        for user in StoredValues[.User.users] where newAccounts[user.id] == nil {
            guard !user.isChildAudience,
                  let token = user.storedAccessToken,
                  let server = servers.first(where: { $0.id == user.serverID })
            else { continue }

            let cacheKey = "\(server.id)|\(server.effectiveServerURL.absoluteString)|\(user.id)|\(token)"
            let session: UserSession

            if let cached = sessionCache[cacheKey] {
                session = cached
            } else {
                // Inert member session: its own device id, so it never takes over anyone's server session
                session = UserSession(
                    server: server,
                    user: user,
                    couch: nil,
                    isCouchMember: true
                )
                sessionCache[cacheKey] = session
            }

            usedCacheKeys.insert(cacheKey)
            newAccounts[user.id] = Account(
                user: user,
                server: server,
                session: session,
                isRestricted: user.isRestricted
            )
        }

        sessionCache = sessionCache.filter { usedCacheKeys.contains($0.key) }
        accounts = newAccounts

        // Forget what belonged to accounts that are gone (signed out of the app, now a kid)
        latestPolls = latestPolls.filter { newAccounts[$0.key] != nil }
        ballots = ballots.filter { newAccounts[$0.key] != nil }
        ballotFetchedPollIDs = ballotFetchedPollIDs.filter { newAccounts[$0.key] != nil }
        failingUserIDs = failingUserIDs.filter { newAccounts[$0] != nil }
    }

    private func targets(for userIDs: [String]) -> [Target] {
        userIDs.compactMap { userID in
            accounts[userID].map { Target(userID: userID, client: $0.session.client) }
        }
    }
}

// MARK: - State

extension CouchVoteParticipant {

    private func listenTick() async -> Duration {
        await refreshNow()

        return poll?.state == .open ? CouchVoteSync.participantActiveInterval : CouchVoteSync.participantIdleInterval
    }

    private func applyPollReads(_ reads: [PollRead]) {
        for read in reads {
            if let error = read.error {
                // Keep the last known poll: one failed read mustn't close the prompt
                if error.isNotEmpty, failingUserIDs.insert(read.userID).inserted {
                    logger.error("Couch vote: reading the poll of user \(read.userID) failed: \(error)")
                }
                continue
            }

            failingUserIDs.remove(read.userID)
            latestPolls[read.userID] = read.poll
        }
    }

    /// The poll to show: the newest promptable one, else the outcome of the last one this device prompted for.
    private func visiblePoll(now: Date) -> CouchVotePoll? {
        if let promptable = CouchVoteSync.promptablePoll(
            in: latestPolls,
            deviceID: UIDevice.vendorUUIDString,
            dismissedPollIDs: dismissedPollIDs,
            now: now
        ) {
            promptedPollIDs.insert(promptable.id)
            shownPollID = promptable.id

            // Another account's copy may already be closed (the host writes them in parallel)
            return CouchVoteSync.freshestPoll(id: promptable.id, in: latestPolls) ?? promptable
        }

        if let shownPollID,
           promptedPollIDs.contains(shownPollID),
           !dismissedPollIDs.contains(shownPollID),
           let latest = CouchVoteSync.freshestPoll(id: shownPollID, in: latestPolls),
           latest.state != .open,
           CouchVoteSync.isShowingResult(latest, now: now)
        {
            return latest
        }

        return nil
    }

    /// Reads each voter's own ballot once per poll, so a vote from before an app restart shows as chosen.
    private func fetchBallotsIfNeeded() async {
        guard let poll = visiblePoll(now: .now) else { return }

        let pollID = poll.id
        let userIDs = CouchVoteSync.voterIDs(for: poll, in: latestPolls)
            .filter { ballotFetchedPollIDs[$0] != pollID }

        guard userIDs.isNotEmpty else { return }

        let reads = await Self.fetchBallots(targets(for: userIDs), pollID: pollID)

        for read in reads {
            if let error = read.error {
                if !error.isEmpty {
                    logger.error("Couch vote: reading the ballot of user \(read.userID) failed: \(error)")
                }
                continue
            }

            // A vote sent meanwhile is newer than what was read
            guard ballotFetchedPollIDs[read.userID] != read.pollID, accounts[read.userID] != nil else { continue }

            ballots[read.userID] = read.ballot
            ballotFetchedPollIDs[read.userID] = read.pollID
        }
    }

    /// Tells the host, once per poll and account, that this phone has seen an open poll for that account.
    private func sendPresenceIfNeeded() {
        guard let poll, poll.state == .open else { return }

        let now = Date.now
        let deviceID = UIDevice.vendorUUIDString

        for (userID, stored) in latestPolls where stored.id == poll.id {
            let key = "\(poll.id)|\(userID)"

            guard !presenceSentKeys.contains(key),
                  CouchVoteSync.isPromptable(stored, userID: userID, deviceID: deviceID, dismissedPollIDs: dismissedPollIDs, now: now),
                  let account = accounts[userID]
            else { continue }

            presenceSentKeys.insert(key)

            let presence = CouchVotePresence(pollID: poll.id, seenAt: now)
            let client = account.session.client

            Task { [weak self] in
                do {
                    try await CouchVoteService.writePresence(presence, userID: userID, client: client)
                } catch {
                    // Try again on the next read
                    self?.presenceSentKeys.remove(key)
                    self?.logger.error("Couch vote: writing the presence of user \(userID) failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func evaluate() {
        let visible = visiblePoll(now: .now)

        if visible != poll {
            poll = visible
        }

        guard let visible else {
            setVoters([], votingAs: nil, choice: nil, voted: [])
            return
        }

        let voterIDs = CouchVoteSync.voterIDs(for: visible, in: latestPolls)
        let newVoters: [CouchVoteVoter] = voterIDs.compactMap { userID in
            accounts[userID].map { CouchVoteVoter(user: $0.user, server: $0.server, isRestricted: $0.isRestricted) }
        }

        var votingAs = votingAsUserID
        if votingAsPollID != visible.id || !voterIDs.contains(votingAs ?? "") {
            votingAs = CouchVoteSync.defaultVoterID(
                voterIDs: voterIDs,
                restrictedIDs: Set(newVoters.filter(\.isRestricted).map(\.id)),
                preferredOrder: Defaults[.Couch.lastMemberIDs]
            )
            votingAsPollID = visible.id
        }

        var choice: CouchVoteChoice?
        if let votingAs {
            choice = CouchVoteSync.choice(of: votingAs, in: visible, ballot: ballots[votingAs])
        }

        let voted = Set(voterIDs.filter { CouchVoteSync.choice(of: $0, in: visible, ballot: ballots[$0]) != nil })

        setVoters(newVoters, votingAs: votingAs, choice: choice, voted: voted)
    }

    /// Publishes only what changed.
    private func setVoters(_ newVoters: [CouchVoteVoter], votingAs: String?, choice: CouchVoteChoice?, voted: Set<String>) {
        if newVoters != voters {
            voters = newVoters
        }
        if votingAs != votingAsUserID {
            votingAsUserID = votingAs
        }
        if choice != myChoice {
            myChoice = choice
        }
        if voted != votedVoterIDs {
            votedVoterIDs = voted
        }
    }
}

// MARK: - Network (nonisolated, runs in parallel)

extension CouchVoteParticipant {

    /// - Returns: one read per target; `error` is `""` for a cancelled read (not worth logging).
    private nonisolated static func fetchPolls(_ targets: [Target]) async -> [PollRead] {
        await withTaskGroup(of: PollRead.self) { group in
            for target in targets {
                group.addTask {
                    do {
                        let poll = try await CouchVoteService.fetchPoll(userID: target.userID, client: target.client)
                        return PollRead(userID: target.userID, poll: poll, error: nil)
                    } catch is CancellationError {
                        return PollRead(userID: target.userID, poll: nil, error: "")
                    } catch {
                        return PollRead(userID: target.userID, poll: nil, error: error.localizedDescription)
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

    /// - Returns: one read per target; `error` is `""` for a cancelled read (not worth logging).
    private nonisolated static func fetchBallots(_ targets: [Target], pollID: String) async -> [BallotRead] {
        await withTaskGroup(of: BallotRead.self) { group in
            for target in targets {
                group.addTask {
                    do {
                        let ballot = try await CouchVoteService.fetchBallot(userID: target.userID, client: target.client)
                        return BallotRead(userID: target.userID, pollID: pollID, ballot: ballot, error: nil)
                    } catch is CancellationError {
                        return BallotRead(userID: target.userID, pollID: pollID, ballot: nil, error: "")
                    } catch {
                        return BallotRead(userID: target.userID, pollID: pollID, ballot: nil, error: error.localizedDescription)
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
}
