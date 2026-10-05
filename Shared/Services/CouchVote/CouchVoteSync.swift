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
/// - `swiftfin-couch-vote-ballot` / `sgw.vote.ballot` in each participant's account: written only by that person's phones.
///
/// Every write is a whole-row replace of one key, so there is no read-modify-write and no lost update.
///
/// Foundation only: this file is type-checked and unit-tested on Linux.
enum CouchVoteSync {

    static let pollPrefsID = "swiftfin-couch-vote-poll"
    static let ballotPrefsID = "swiftfin-couch-vote-ballot"
    static let pollKey = "sgw.vote.poll"
    static let ballotKey = "sgw.vote.ballot"
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
    static func voteTime(after previous: Date?, now: Date) -> Date {
        guard let previous, previous >= now else { return now }

        return previous.addingTimeInterval(0.001)
    }
}
