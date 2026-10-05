//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

// MARK: - Couch vote ("Vote for tonight")

extension L10n {

    enum CouchVote {

        /// Decider action that starts a vote on everyone's phone.
        static let letEveryoneVote = "Let everyone vote"

        /// Title of the vote screen (TV) and the ballot sheet (phone).
        static let voteForTonight = "Vote for tonight"

        /// Primary button that starts the vote.
        static let startVote = "Start the vote"

        /// Shown while the poll is being written to everyone's account.
        static let startingVote = "Starting the vote…"

        /// Banner when no phone account could be reached.
        static let phonesUnreachable = "Phones can't be reached; vote here on the TV"

        /// Ends the vote before its deadline.
        static let closeVoteNow = "Close vote now"

        /// Cancels the vote.
        static let cancelVote = "Cancel vote"

        /// Confirmation title before cancelling an open vote.
        static let cancelVoteConfirm = "Cancel the vote?"

        /// Dismisses the cancel confirmation and keeps the vote open.
        static let keepVoting = "Keep voting"

        /// Title of the "vote on behalf of someone" menu on the TV.
        static let voteAs = "Vote as…"

        /// e.g. "2 of 4 voted"
        static func votedCount(_ voted: Int, _ total: Int) -> String {
            "\(voted) of \(total) voted"
        }

        /// e.g. "Sam & Lisa's couch"
        ///
        /// - Parameter names: A localized list of names, e.g. `CouchGroup.displayNames`.
        static func couchVoting(_ names: String) -> String {
            "\(names)'s couch"
        }

        /// Precedes the countdown timer, e.g. "closes in 0:52".
        static let closesIn = "closes in"

        /// The abstain choice: counts as voted, for no title in particular.
        static let anythingsFine = "Anything's fine"

        /// e.g. "Tonight: Toy Story"
        static func tonight(_ title: String) -> String {
            "Tonight: \(title)"
        }

        /// e.g. "Tonight: Toy Story 🎉" (phone result card)
        static func tonightCelebration(_ title: String) -> String {
            "Tonight: \(title) 🎉"
        }

        /// Shown on the phone when the TV cancelled the vote.
        static let voteCancelled = "Vote cancelled"

        /// Shown on the phone when the vote disappeared without a result.
        static let voteEnded = "The vote has ended"

        /// Member state: their phone confirmed that it has the vote.
        static let votingOnPhone = "Voting on their phone"

        /// Member state: the vote was sent to their account, their phone hasn't picked it up yet.
        static let canVoteOnPhone = "Can vote on their phone"

        /// Member state: no phone account, votes on the TV.
        static let votesHere = "Votes here"

        /// Member state: their phone account stopped answering.
        static let unreachable = "Unreachable"

        /// Member state: they are voting in another TV's vote.
        static let votingElsewhere = "Voting elsewhere"

        /// Member state: their vote is in.
        static let voted = "Voted"

        /// Dismisses the vote screen after the reveal.
        static let backToDecider = "Back to the decider"

        /// Plays the winner.
        static let watch = "Watch"

        /// Header above the option count chips.
        static let howManyOptions = "How many titles?"

        /// e.g. "4 titles"
        static func optionCount(_ n: Int) -> String {
            n == 1 ? "1 title" : "\(n) titles"
        }

        /// e.g. "3 votes"
        static func voteCount(_ n: Int) -> String {
            n == 1 ? "1 vote" : "\(n) votes"
        }

        /// Explains how to vote on the TV (nobody can vote on a phone).
        static let hostVoteHint = "Select a title to vote for someone on the couch"

        /// Explains how to join from a phone, and how to vote on the TV.
        static let joinHint = "Open Couchfin on your iPhone to vote · or select a title to vote for someone here"

        /// "Vote as…" entry of someone whose vote came from their phone, e.g. "Sam ✓ (on phone)".
        static func votedOnPhone(_ name: String) -> String {
            "\(name) ✓ (on phone)"
        }

        /// "Vote as…" entry of someone whose vote was cast on the TV, e.g. "Lisa ✓ (Toy Story)".
        static func votedHere(_ name: String, _ choice: String) -> String {
            "\(name) ✓ (\(choice))"
        }

        /// Label above the phone's voter avatars.
        static let votingAs = "Voting as"

        /// VoiceOver hint of a voter avatar on the phone, e.g. "Your next vote counts for Lisa".
        static func votingAsHint(_ name: String) -> String {
            "Your next vote counts for \(name)"
        }

        /// VoiceOver hint of a ballot row, e.g. "Votes as Sam".
        static func votesAs(_ name: String) -> String {
            "Votes as \(name)"
        }

        /// VoiceOver value of a ballot row while its vote is being sent.
        static let sending = "Sending"

        /// Explains the phone ballot.
        static let ballotHint = "Tap a title to vote. You can change your mind until the vote closes."

        /// Shown under the winner when it was a tie.
        static let tieBreak = "It was a tie, so the deck's favourite won"

        /// Shown while the TV waits for the reveal.
        static let countingVotes = "Counting the votes…"

        /// Shown when the vote closed with no options.
        static let noWinner = "No winner this time"

        /// Shown when the vote screen cannot find a signed-in account.
        static let notSignedIn = "Sign in to start a vote"
    }
}
