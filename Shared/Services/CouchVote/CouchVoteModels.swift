//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

// "Vote for tonight": a couch votes between a few titles, from their own iPhones or on the TV.
//
// Foundation only: this file is type-checked and unit-tested on Linux.

/// One title on the ballot.
struct CouchVoteOption: Codable, Hashable, Identifiable, Sendable {

    /// The Jellyfin item id.
    var id: String
    var title: String
    /// e.g. "2019 · 1h 52m" or "S2 · E5 · 42m".
    var subtitle: String?
    /// "movie", "series" or "episode".
    var kind: String

    init(id: String, title: String, subtitle: String? = nil, kind: String) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
    }
}

/// One person's vote.
struct CouchVoteChoice: Codable, Hashable, Sendable {

    /// The voted option, or `nil` for "Anything's fine" (an abstention that still counts as voted).
    var optionID: String?
    var votedAt: Date

    init(optionID: String?, votedAt: Date = .now) {
        self.optionID = optionID
        self.votedAt = votedAt
    }
}

/// A vote started by a host device (the TV).
///
/// Written **only by the host**, into the `swiftfin-couch-vote-poll` row of every participant it has a session for.
struct CouchVotePoll: Codable, Hashable, Identifiable, Sendable {

    enum State: String, Codable, Hashable, Sendable {
        case open
        case closed
        case cancelled
    }

    /// `CouchVoteSync.schema` of the writer. Newer schemas are ignored by older apps.
    var schema: Int
    var id: String
    /// `CouchGroup.id`
    var couchID: String
    /// `CouchGroup.displayNames`, e.g. "Sam and Lisa".
    var couchTitle: String
    var hostUserID: String
    /// `UIDevice.vendorUUIDString` of the host, so the host never prompts itself.
    var hostDeviceID: String
    /// Everyone on the couch, in couch order.
    var participantIDs: [String]
    /// 2...5 options, in the deck's order. Ties go to the earliest option.
    var options: [CouchVoteOption]
    var createdAt: Date
    /// From the host clock. Phones add `CouchVoteSync.deadlineGrace` and never close anything themselves.
    var deadline: Date
    var state: State
    /// Votes cast on the host, by user id (people without a phone, or overrides).
    var hostVotes: [String: CouchVoteChoice]
    /// The host's snapshot of who voted, for "2 of 4 voted" on the phones.
    var votedUserIDs: [String]
    var winnerOptionID: String?
    var closedAt: Date?
    var updatedAt: Date

    init(
        schema: Int = CouchVoteSync.schema,
        id: String = UUID().uuidString,
        couchID: String,
        couchTitle: String,
        hostUserID: String,
        hostDeviceID: String,
        participantIDs: [String],
        options: [CouchVoteOption],
        createdAt: Date = .now,
        deadline: Date,
        state: State = .open,
        hostVotes: [String: CouchVoteChoice] = [:],
        votedUserIDs: [String] = [],
        winnerOptionID: String? = nil,
        closedAt: Date? = nil,
        updatedAt: Date = .now
    ) {
        self.schema = schema
        self.id = id
        self.couchID = couchID
        self.couchTitle = couchTitle
        self.hostUserID = hostUserID
        self.hostDeviceID = hostDeviceID
        self.participantIDs = participantIDs
        self.options = options
        self.createdAt = createdAt
        self.deadline = deadline
        self.state = state
        self.hostVotes = hostVotes
        self.votedUserIDs = votedUserIDs
        self.winnerOptionID = winnerOptionID
        self.closedAt = closedAt
        self.updatedAt = updatedAt
    }

    func option(id: String) -> CouchVoteOption? {
        options.first { $0.id == id }
    }
}

/// One person's ballot.
///
/// Written **only by that person's own devices**, into their `swiftfin-couch-vote-ballot` row.
struct CouchVoteBallot: Codable, Hashable, Sendable {

    var schema: Int
    /// The poll this ballot answers. Ballots for another poll are stale (or for another TV's vote).
    var pollID: String
    var userID: String
    var choice: CouchVoteChoice

    init(schema: Int = CouchVoteSync.schema, pollID: String, userID: String, choice: CouchVoteChoice) {
        self.schema = schema
        self.pollID = pollID
        self.userID = userID
        self.choice = choice
    }
}

/// "This phone has seen the vote": proof that someone can really vote on a phone.
///
/// Written **only by that person's own phones**, into their `swiftfin-couch-vote-presence` row,
/// once per poll, when a phone first finds the poll promptable for them. The host reads it to tell
/// "Voting on their phone" from "Can vote on their phone". Older builds never read or write this row.
struct CouchVotePresence: Codable, Hashable, Sendable {

    /// The poll the phone has seen.
    var pollID: String
    /// From the phone's clock.
    var seenAt: Date

    init(pollID: String, seenAt: Date = .now) {
        self.pollID = pollID
        self.seenAt = seenAt
    }
}

/// The live count of a poll, computed by `CouchVoteSync.tally(_:ballots:)`.
struct CouchVoteTally: Equatable, Sendable {

    /// Option id → the user ids that voted for it (sorted). Options without votes are absent.
    var votersByOptionID: [String: [String]]
    /// "Anything's fine" voters.
    var abstainedUserIDs: Set<String>
    /// Everyone with a valid vote, abstentions included.
    var votedUserIDs: Set<String>
    /// The options with the most votes, in `poll.options` order. Empty while no option has a vote.
    var leadingOptionIDs: [String]

    init(
        votersByOptionID: [String: [String]] = [:],
        abstainedUserIDs: Set<String> = [],
        votedUserIDs: Set<String> = [],
        leadingOptionIDs: [String] = []
    ) {
        self.votersByOptionID = votersByOptionID
        self.abstainedUserIDs = abstainedUserIDs
        self.votedUserIDs = votedUserIDs
        self.leadingOptionIDs = leadingOptionIDs
    }

    static let empty = CouchVoteTally()

    func count(for optionID: String) -> Int {
        votersByOptionID[optionID]?.count ?? 0
    }
}
