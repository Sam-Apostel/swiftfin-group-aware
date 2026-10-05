//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

enum CouchVoteError: LocalizedError {

    case encodingFailed
    case pollNotOpen
    case noSession

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            "The vote couldn't be encoded."
        case .pollNotOpen:
            "This vote is closed."
        case .noSession:
            "Not signed in."
        }
    }
}

/// Network access to the vote rows. Every call is a single GET or a whole-row POST of one key.
///
/// Not actor-isolated: callers on the main actor hop off it for the request.
enum CouchVoteService {

    /// The poll in `userID`'s poll row (`nil` when there is none, or it's unreadable).
    static func fetchPoll(userID: String, client: JellyfinClient) async throws -> CouchVotePoll? {
        let customPrefs = try await CouchDisplayPreferences.fetchCustomPrefs(
            displayPreferencesID: CouchVoteSync.pollPrefsID,
            userID: userID,
            client: client
        )
        return CouchVoteSync.poll(in: customPrefs)
    }

    /// Replaces `userID`'s poll row with `poll`. Only the host writes poll rows.
    static func writePoll(_ poll: CouchVotePoll, userID: String, client: JellyfinClient) async throws {
        guard let value = CouchVoteSync.encode(poll) else {
            throw CouchVoteError.encodingFailed
        }

        try await CouchDisplayPreferences.postCustomPrefs(
            [CouchVoteSync.pollKey: value],
            displayPreferencesID: CouchVoteSync.pollPrefsID,
            userID: userID,
            client: client
        )
    }

    /// The ballot in `userID`'s ballot row (`nil` when there is none, or it's unreadable).
    static func fetchBallot(userID: String, client: JellyfinClient) async throws -> CouchVoteBallot? {
        let customPrefs = try await CouchDisplayPreferences.fetchCustomPrefs(
            displayPreferencesID: CouchVoteSync.ballotPrefsID,
            userID: userID,
            client: client
        )
        return CouchVoteSync.ballot(in: customPrefs)
    }

    /// Replaces the ballot row of `ballot.userID`. Only that person's own devices write it.
    static func writeBallot(_ ballot: CouchVoteBallot, client: JellyfinClient) async throws {
        guard let value = CouchVoteSync.encode(ballot) else {
            throw CouchVoteError.encodingFailed
        }

        try await CouchDisplayPreferences.postCustomPrefs(
            [CouchVoteSync.ballotKey: value],
            displayPreferencesID: CouchVoteSync.ballotPrefsID,
            userID: ballot.userID,
            client: client
        )
    }

    /// The presence in `userID`'s presence row (`nil` when there is none, or it's unreadable).
    static func fetchPresence(userID: String, client: JellyfinClient) async throws -> CouchVotePresence? {
        let customPrefs = try await CouchDisplayPreferences.fetchCustomPrefs(
            displayPreferencesID: CouchVoteSync.presencePrefsID,
            userID: userID,
            client: client
        )
        return CouchVoteSync.presence(in: customPrefs)
    }

    /// Replaces `userID`'s presence row. Only that person's own phones write it.
    static func writePresence(_ presence: CouchVotePresence, userID: String, client: JellyfinClient) async throws {
        guard let value = CouchVoteSync.encode(presence) else {
            throw CouchVoteError.encodingFailed
        }

        try await CouchDisplayPreferences.postCustomPrefs(
            [CouchVoteSync.presenceKey: value],
            displayPreferencesID: CouchVoteSync.presencePrefsID,
            userID: userID,
            client: client
        )
    }
}
