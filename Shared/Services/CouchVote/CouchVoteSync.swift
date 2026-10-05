//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// Storage format and rules of "Vote for tonight".
///
/// Storage: Jellyfin DisplayPreferences (client `swiftfin-couch`), one JSON document per row, single writer per row:
/// - `swiftfin-couch-vote-poll` / `sgw.vote.poll` in each participant's account: written only by the host (TV);
/// - `swiftfin-couch-vote-ballot` / `sgw.vote.ballot` in each participant's account: written only by that person's phones;
/// - `swiftfin-couch-vote-presence` / `sgw.vote.presence` in each participant's account: written only by that person's
///   phones, once per poll, when a phone first sees it (`CouchVotePresence`). Older builds ignore this row.
///
/// Every write is a whole-row replace of one key, so there is no read-modify-write and no lost update.
/// (`postCustomPrefs` replaces the whole map of a DisplayPreferences id, so every kind of row has its own id.)
///
/// Kids (`UserState.isChildAudience`) never get a poll row and are never listened for: they vote on the host.
///
/// Foundation only: this file is type-checked and unit-tested on Linux.
enum CouchVoteSync {

    static let pollPrefsID = "swiftfin-couch-vote-poll"
    static let ballotPrefsID = "swiftfin-couch-vote-ballot"
    static let presencePrefsID = "swiftfin-couch-vote-presence"
    static let pollKey = "sgw.vote.poll"
    static let ballotKey = "sgw.vote.ballot"
    static let presenceKey = "sgw.vote.presence"
    static let schema = 1

    /// How long a vote stays open by default.
    static let defaultDuration: TimeInterval = 90
    /// Phones keep an open poll promptable this long after its deadline (clock skew, a host that disappeared).
    static let deadlineGrace: TimeInterval = 30
    /// Phones show the result this long after the vote closed.
    static let resultVisibility: TimeInterval = 120
    /// The host closes this long after everyone has voted, so a last-second change still counts.
    static let allVotedSettle: TimeInterval = 3
    /// Minimum time between two `votedUserIDs` updates of the poll rows.
    static let votedUpdateThrottle: TimeInterval = 3
    /// Consecutive failed ballot reads after which a member shows as unreachable.
    static let unreachableAfterFailures = 3
    static let maxOptions = 5
    /// A member whose phone hasn't confirmed the poll (`CouchVotePresence`) this long after it was sent
    /// shows as "Votes here". Phones read every 10 s while idle, so this allows one missed read plus latency.
    static let presenceFallback: TimeInterval = 20

    static let hostPollInterval: Duration = .seconds(2)
    static let participantIdleInterval: Duration = .seconds(10)
    static let participantActiveInterval: Duration = .seconds(2)

    // MARK: - Coding

    /// JSON with dates as integer milliseconds since 1970 (`AudienceWatchlistSync.makeEncoder()`).
    static func encode(_ value: some Encodable) -> String? {
        guard let data = try? AudienceWatchlistSync.makeEncoder().encode(value) else { return nil }

        return String(data: data, encoding: .utf8)
    }

    static func decode<T: Decodable>(_ type: T.Type, from value: String) -> T? {
        guard let data = value.data(using: .utf8) else { return nil }

        return try? AudienceWatchlistSync.makeDecoder().decode(type, from: data)
    }

    /// The poll stored in a poll row. `nil` when missing, undecodable or written with a newer schema.
    static func poll(in customPrefs: [String: String?]) -> CouchVotePoll? {
        guard let value = customPrefs[pollKey] ?? nil,
              let poll = decode(CouchVotePoll.self, from: value),
              poll.schema <= schema
        else { return nil }

        return poll
    }

    /// The ballot stored in a ballot row. `nil` when missing, undecodable or written with a newer schema.
    static func ballot(in customPrefs: [String: String?]) -> CouchVoteBallot? {
        guard let value = customPrefs[ballotKey] ?? nil,
              let ballot = decode(CouchVoteBallot.self, from: value),
              ballot.schema <= schema
        else { return nil }

        return ballot
    }

    /// The presence stored in a presence row. `nil` when missing or undecodable.
    static func presence(in customPrefs: [String: String?]) -> CouchVotePresence? {
        guard let value = customPrefs[presenceKey] ?? nil else { return nil }

        return decode(CouchVotePresence.self, from: value)
    }

    // MARK: - Presence (host)

    /// Whether `presence` proves that a phone has seen `poll`.
    static func isPresent(_ presence: CouchVotePresence?, for poll: CouchVotePoll) -> Bool {
        presence?.pollID == poll.id
    }

    /// Whether a phone member without presence still shows as "Can vote on their phone"
    /// (else "Votes here"). `sentAt` is when the poll reached their account.
    static func isWaitingForPresence(sentAt: Date, now: Date) -> Bool {
        now < sentAt.addingTimeInterval(presenceFallback)
    }

    // MARK: - Participant rules

    /// Whether a phone signed in as `userID` should prompt for this poll.
    static func isPromptable(
        _ poll: CouchVotePoll,
        userID: String,
        deviceID: String,
        dismissedPollIDs: Set<String>,
        now: Date
    ) -> Bool {
        poll.state == .open
            && now < poll.deadline.addingTimeInterval(deadlineGrace)
            && poll.participantIDs.contains(userID)
            && poll.hostDeviceID != deviceID
            && !dismissedPollIDs.contains(poll.id)
    }

    /// The poll a phone should prompt for, from the poll rows of every account it listens for (keyed by user id):
    /// the newest poll that is promptable for at least one of them. Ties go to the smaller id, so it's deterministic.
    static func promptablePoll(
        in pollsByUserID: [String: CouchVotePoll],
        deviceID: String,
        dismissedPollIDs: Set<String>,
        now: Date
    ) -> CouchVotePoll? {
        var best: CouchVotePoll?

        for (userID, poll) in pollsByUserID {
            guard isPromptable(poll, userID: userID, deviceID: deviceID, dismissedPollIDs: dismissedPollIDs, now: now) else {
                continue
            }

            if let current = best {
                if poll.createdAt > current.createdAt || (poll.createdAt == current.createdAt && poll.id < current.id) {
                    best = poll
                }
            } else {
                best = poll
            }
        }

        return best
    }

    /// The freshest copy of poll `pollID` among the rows (the host may have reached some accounts and not others):
    /// the latest `updatedAt`; on a tie a finished copy beats an open one.
    static func freshestPoll(id pollID: String, in pollsByUserID: [String: CouchVotePoll]) -> CouchVotePoll? {
        var best: CouchVotePoll?

        for poll in pollsByUserID.values where poll.id == pollID {
            if let current = best {
                if poll.updatedAt > current.updatedAt || (poll.updatedAt == current.updatedAt && current.state == .open) {
                    best = poll
                }
            } else {
                best = poll
            }
        }

        return best
    }

    /// The listened accounts that can vote in `poll` with this phone, in the poll's participant order:
    /// participants whose own poll row holds this poll (the host reads exactly their ballots).
    static func voterIDs(for poll: CouchVotePoll, in pollsByUserID: [String: CouchVotePoll]) -> [String] {
        poll.participantIDs.filter { pollsByUserID[$0]?.id == poll.id }
    }

    /// Who a phone votes as until someone taps another avatar: in `preferredOrder` (the phone's last couch,
    /// in pick order), then the poll's order, the first voter who isn't restricted, else the first voter.
    static func defaultVoterID(
        voterIDs: [String],
        restrictedIDs: Set<String>,
        preferredOrder: [String]
    ) -> String? {
        var ordered: [String] = []
        for userID in preferredOrder + voterIDs where voterIDs.contains(userID) && !ordered.contains(userID) {
            ordered.append(userID)
        }

        return ordered.first { !restrictedIDs.contains($0) } ?? ordered.first
    }

    /// Whether a phone should still show the outcome of this poll (winner, or "Vote cancelled").
    static func isShowingResult(_ poll: CouchVotePoll, now: Date) -> Bool {
        guard poll.state != .open else { return false }

        let closedAt = poll.closedAt ?? poll.updatedAt
        return now < closedAt.addingTimeInterval(resultVisibility)
    }

    // MARK: - Tally

    /// The later of two votes of the same person. On an exact tie the `preferred` vote wins.
    static func latest(_ preferred: CouchVoteChoice?, _ other: CouchVoteChoice?) -> CouchVoteChoice? {
        guard let preferred else { return other }
        guard let other else { return preferred }

        return other.votedAt > preferred.votedAt ? other : preferred
    }

    /// Whether `choice` is a vote this poll can count: an abstention or one of its options.
    static func isValid(_ choice: CouchVoteChoice, in poll: CouchVotePoll) -> Bool {
        guard let optionID = choice.optionID else { return true }

        return poll.options.contains { $0.id == optionID }
    }

    /// A person's effective vote: the latest valid one between their phone ballot (only if it answers this poll)
    /// and the vote cast for them on the host.
    static func choice(
        of userID: String,
        in poll: CouchVotePoll,
        ballot: CouchVoteBallot?
    ) -> CouchVoteChoice? {
        var phoneChoice: CouchVoteChoice?
        if let ballot, ballot.pollID == poll.id, ballot.userID == userID, isValid(ballot.choice, in: poll) {
            phoneChoice = ballot.choice
        }

        var hostChoice: CouchVoteChoice?
        if let vote = poll.hostVotes[userID], isValid(vote, in: poll) {
            hostChoice = vote
        }

        return latest(hostChoice, phoneChoice)
    }

    /// Counts the votes of the poll's participants. `ballots` are keyed by user id.
    ///
    /// Ignored: ballots of another poll, non-participants, and votes for options that aren't on this poll.
    static func tally(_ poll: CouchVotePoll, ballots: [String: CouchVoteBallot]) -> CouchVoteTally {
        var result = CouchVoteTally()

        for userID in poll.participantIDs where !result.votedUserIDs.contains(userID) {
            guard let choice = choice(of: userID, in: poll, ballot: ballots[userID]) else { continue }

            result.votedUserIDs.insert(userID)

            if let optionID = choice.optionID {
                result.votersByOptionID[optionID, default: []].append(userID)
            } else {
                result.abstainedUserIDs.insert(userID)
            }
        }

        for optionID in result.votersByOptionID.keys {
            result.votersByOptionID[optionID]?.sort()
        }

        let maxCount = poll.options.map { result.count(for: $0.id) }.max() ?? 0

        if maxCount > 0 {
            var leading: [String] = []
            for option in poll.options where result.count(for: option.id) == maxCount && !leading.contains(option.id) {
                leading.append(option.id)
            }
            result.leadingOptionIDs = leading
        }

        return result
    }

    /// The winning option: most votes; a tie goes to the earliest option in `poll.options`;
    /// without any votes, the first option. Deterministic on every device.
    static func winner(of poll: CouchVotePoll, tally: CouchVoteTally) -> String? {
        tally.leadingOptionIDs.first ?? poll.options.first?.id
    }

    /// Whether every participant has a valid vote (abstentions included).
    static func everyoneVoted(_ poll: CouchVotePoll, tally: CouchVoteTally) -> Bool {
        !poll.participantIDs.isEmpty && poll.participantIDs.allSatisfy { tally.votedUserIDs.contains($0) }
    }

    /// `votedUserIDs` in participant order, as stored in the poll.
    static func orderedVotedUserIDs(_ poll: CouchVotePoll, tally: CouchVoteTally) -> [String] {
        poll.participantIDs.filter { tally.votedUserIDs.contains($0) }
    }

    /// A vote time that's strictly later than `previous`, even when this device's clock is behind.
    ///
    /// At least 1 ms later: dates are stored as whole milliseconds, so a smaller step could round to a tie.
    static func voteTime(after previous: Date?, now: Date) -> Date {
        guard let previous else { return now }

        let earliest = previous.addingTimeInterval(0.001)
        return now >= earliest ? now : earliest
    }
}
