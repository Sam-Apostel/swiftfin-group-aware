//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import FactoryKit
import JellyfinAPI
import Logging
import SwiftUI
import UIKit

/// The phone's "Vote for tonight" ballot, presented by `couchVotePrompt()`.
///
/// "Voting as" shows the grown-ups on the couch this phone can vote for (never a kid); tapping an avatar
/// switches who the next tap votes for. Tapping a row votes right away; tapping another row changes the vote.
/// It shows the result when the TV closes the vote, then dismisses itself.
struct CouchVoteBallotView: View {

    /// What a row stands for. `anything` is the "Anything's fine" abstention.
    private enum Choice: Hashable {
        case option(String)
        case anything

        init(optionID: String?) {
            if let optionID {
                self = .option(optionID)
            } else {
                self = .anything
            }
        }

        var optionID: String? {
            switch self {
            case let .option(id):
                id
            case .anything:
                nil
            }
        }
    }

    @Default(.accentColor)
    private var accentColor

    @Environment(\.dismiss)
    private var dismiss

    @ObservedObject
    private var participant: CouchVoteParticipant

    /// The last poll seen, so the sheet can still say "Vote cancelled"
    /// after the participant stops publishing the poll.
    @State
    private var displayedPoll: CouchVotePoll?
    @State
    private var items: [String: BaseItemDto] = [:]
    /// A vote being sent (or that failed), for one voter on this phone.
    private struct PendingVote: Equatable {
        let userID: String
        let choice: Choice
    }

    @State
    private var pendingVote: PendingVote?
    @State
    private var failedVote: PendingVote?
    @State
    private var error: Error?
    @State
    private var selectionTrigger = 0
    @State
    private var celebrationTrigger = 0

    private let logger = Logger.swiftfin()

    init(participant: CouchVoteParticipant) {
        self.participant = participant
        self._displayedPoll = State(initialValue: participant.poll)
    }

    // MARK: - State

    private enum Stage: Equatable {
        case voting
        case closed(winnerOptionID: String?)
        case cancelled
        case ended
    }

    private var stage: Stage {
        guard let poll = displayedPoll else { return .ended }

        // The participant only publishes polls that are promptable or showing a result.
        // A poll that disappeared while open was cancelled, expired or taken over.
        if participant.poll?.id != poll.id, poll.state == .open {
            return .ended
        }

        switch poll.state {
        case .open:
            return .voting
        case .closed:
            return .closed(winnerOptionID: poll.winnerOptionID)
        case .cancelled:
            return .cancelled
        }
    }

    /// The vote being sent for the person this phone votes as now.
    private var currentPendingVote: PendingVote? {
        guard let pendingVote, pendingVote.userID == participant.votingAsUserID else { return nil }

        return pendingVote
    }

    private var selectedChoice: Choice? {
        if let currentPendingVote {
            return currentPendingVote.choice
        }

        return participant.myChoice.map { Choice(optionID: $0.optionID) }
    }

    private func isPending(_ choice: Choice) -> Bool {
        currentPendingVote?.choice == choice && participant.isSending
    }

    private var votingAsName: String? {
        participant.voters.first { $0.id == participant.votingAsUserID }?.user.username
    }

    // MARK: - Actions

    private func vote(_ choice: Choice) {
        guard let userID = participant.votingAsUserID else { return }

        send(PendingVote(userID: userID, choice: choice))
    }

    private func send(_ vote: PendingVote) {
        guard stage == .voting, !participant.isSending || pendingVote != vote else { return }

        pendingVote = vote
        failedVote = nil
        error = nil
        selectionTrigger += 1

        Task {
            do {
                try await participant.vote(optionID: vote.choice.optionID, as: vote.userID)
            } catch {
                logger.error("Couch vote failed: \(error.localizedDescription)")
                failedVote = vote
                self.error = error
            }

            if pendingVote == vote {
                pendingVote = nil
            }
        }
    }

    private func retry() {
        guard let failedVote else { return }

        send(failedVote)
    }

    private func selectVoter(_ voter: CouchVoteVoter) {
        guard participant.votingAsUserID != voter.id else { return }

        selectionTrigger += 1
        participant.selectVoter(userID: voter.id)
    }

    private func loadPosters(for poll: CouchVotePoll) async {
        // A voter's own account on this phone (works signed out); the TV's session isn't available here
        let voterSession = (participant.votingAsUserID ?? participant.voters.first?.id)
            .flatMap { participant.session(forVoterID: $0) }

        guard let session = voterSession ?? Container.shared.currentUserSession() else { return }

        let ids = poll.options.map(\.id).filter { items[$0] == nil }
        guard ids.isNotEmpty else { return }

        do {
            let fetched = try await CouchItemFilter.fetchItems(ids: ids, session: session)

            for item in fetched {
                if let id = item.id {
                    items[id] = item
                }
            }
        } catch {
            // Rows fall back to a film symbol
            logger.error("Couch vote posters failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func header(_ poll: CouchVotePoll) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.CouchVote.voteForTonight)
                .font(.title2)
                .fontWeight(.bold)

            DotHStack {
                Text(L10n.CouchVote.couchVoting(poll.couchTitle))
                    .lineLimit(1)

                if stage == .voting {
                    HStack(spacing: 4) {
                        Text(L10n.CouchVote.closesIn)

                        Text(
                            timerInterval: min(poll.createdAt, poll.deadline) ... poll.deadline,
                            countsDown: true
                        )
                        .monospacedDigit()
                    }
                    // "closes in 0:52" is read as one element
                    .accessibilityElement(children: .combine)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Text(L10n.CouchVote.votedCount(poll.votedUserIDs.count, poll.participantIDs.count))
                .font(.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .animation(.default, value: poll.votedUserIDs.count)

            votingAsRow
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Voting as

    @ViewBuilder
    private func voterAvatar(_ voter: CouchVoteVoter, hasVoted: Bool) -> some View {
        UserProfileImage(
            userID: voter.id,
            source: voter.user.profileImageSource(
                client: voter.server.client
            ),
            pipeline: .Swiftfin.local
        )
        .frame(width: 32, height: 32)
        .overlay(alignment: .bottomTrailing) {
            if hasVoted {
                // Who on this phone has already voted
                Image(systemName: "checkmark.circle.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(accentColor.overlayColor, accentColor)
                    .frame(width: 14, height: 14)
                    .offset(x: 3, y: 2)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    @ViewBuilder
    private func voterChip(_ voter: CouchVoteVoter) -> some View {
        let isSelected = participant.votingAsUserID == voter.id
        let hasVoted = participant.votedVoterIDs.contains(voter.id)

        Button {
            selectVoter(voter)
        } label: {
            HStack(spacing: 8) {
                voterAvatar(voter, hasVoted: hasVoted)

                Text(voter.user.username)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }
            .padding(.leading, 4)
            .padding(.trailing, 12)
            .padding(.vertical, 4)
            .background {
                Capsule()
                    .fill(isSelected ? AnyShapeStyle(accentColor.opacity(0.18)) : AnyShapeStyle(Color.secondarySystemFill))
            }
            .overlay {
                if isSelected {
                    Capsule()
                        .stroke(accentColor, lineWidth: 2)
                }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .disabled(stage != .voting)
        .accessibilityLabel(voter.user.username)
        .accessibilityValue(hasVoted ? L10n.CouchVote.voted : "")
        .accessibilityHint(L10n.CouchVote.votingAsHint(voter.user.username))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// The grown-ups on this phone that take part in the vote. Shown even for one, so it's clear who votes.
    @ViewBuilder
    private var votingAsRow: some View {
        if participant.voters.isNotEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.CouchVote.votingAs)
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)

                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(participant.voters) { voter in
                            voterChip(voter)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            }
            .animation(.easeInOut(duration: 0.2), value: participant.votingAsUserID)
            .animation(.easeInOut(duration: 0.2), value: participant.votedVoterIDs)
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func rowPoster(_ option: CouchVoteOption) -> some View {
        if let item = items[option.id] {
            PosterImage(
                item: item,
                type: .portrait,
                size: .small
            )
        } else {
            ZStack {
                Rectangle()
                    .fill(.complexSecondary)

                SystemImageContentView(systemName: "film")
            }
            .posterStyle(.portrait)
        }
    }

    @ViewBuilder
    private func selectionIndicator(_ choice: Choice) -> some View {
        if isPending(choice) {
            ProgressView()
                .frame(width: 26, height: 26)
        } else if selectedChoice == choice {
            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .symbolRenderingMode(.palette)
                .foregroundStyle(accentColor.overlayColor, accentColor)
                .frame(width: 26, height: 26)
                .transition(.scale.combined(with: .opacity))
        } else {
            Image(systemName: "circle")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
        }
    }

    @ViewBuilder
    private func row(
        choice: Choice,
        @ViewBuilder leading: () -> some View,
        @ViewBuilder label: () -> some View
    ) -> some View {
        let isSelected = selectedChoice == choice

        Button {
            vote(choice)
        } label: {
            HStack(spacing: 12) {
                leading()
                    .frame(width: 48)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    label()
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // The state is read as the selected trait and the value
                selectionIndicator(choice)
                    .accessibilityHidden(true)
            }
            .padding(10)
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? AnyShapeStyle(accentColor.opacity(0.18)) : AnyShapeStyle(Color.secondarySystemFill))
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(accentColor, lineWidth: 2)
                }
            }
            .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary, .secondary)
        .disabled(stage != .voting)
        // VoiceOver: "Toy Story, selected"
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(isPending(choice) ? L10n.CouchVote.sending : "")
        .accessibilityHint(votingAsName.map { L10n.CouchVote.votesAs($0) } ?? "")
    }

    @ViewBuilder
    private func optionRow(_ option: CouchVoteOption) -> some View {
        row(choice: .option(option.id)) {
            rowPoster(option)
        } label: {
            Text(option.title)
                .font(.callout)
                .fontWeight(.semibold)
                .lineLimit(2)

            if let subtitle = option.subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var anythingRow: some View {
        row(choice: .anything) {
            Image(systemName: "hand.thumbsup.fill")
                .font(.title3)
                .foregroundStyle(accentColor)
                .frame(width: 48, height: 48)
        } label: {
            Text(L10n.CouchVote.anythingsFine)
                .font(.callout)
                .fontWeight(.semibold)
        }
    }

    @ViewBuilder
    private var errorRow: some View {
        if let error {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)

                Text(error.localizedDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button(L10n.retry) {
                    retry()
                }
                .font(.footnote.weight(.semibold))
                .backport
                .buttonStyle(.glass)
                .controlSize(.small)
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private func ballot(_ poll: CouchVotePoll) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(poll)

                VStack(spacing: 10) {
                    ForEach(poll.options) { option in
                        optionRow(option)
                    }

                    anythingRow
                }

                errorRow

                Text(L10n.CouchVote.ballotHint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .edgePadding(.horizontal)
            .padding(.vertical, 20)
        }
        .sensoryFeedback(.selection, trigger: selectionTrigger)
    }

    // MARK: - Results

    @ViewBuilder
    private func winnerCard(_ poll: CouchVotePoll, winnerOptionID: String?) -> some View {
        let winner = poll.options.first { $0.id == winnerOptionID }

        VStack(spacing: 16) {
            Image(systemName: "party.popper.fill")
                .font(.system(size: 56))
                .foregroundStyle(accentColor)
                .symbolEffect(.bounce, value: celebrationTrigger)

            if let winner {
                if let item = items[winner.id] {
                    PosterImage(
                        item: item,
                        type: .portrait,
                        size: .small
                    )
                    .frame(width: 120)
                    .shadow(radius: 10)
                }

                Text(L10n.CouchVote.tonightCelebration(winner.title))
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                if let subtitle = winner.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(L10n.CouchVote.noWinner)
                    .font(.title3)
                    .fontWeight(.semibold)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .edgePadding()
        .sensoryFeedback(.success, trigger: celebrationTrigger)
        .task {
            celebrationTrigger += 1

            if let winner {
                UIAccessibility.post(notification: .announcement, argument: L10n.CouchVote.tonight(winner.title))
            }

            try? await Task.sleep(for: .seconds(8))

            guard !Task.isCancelled else { return }

            dismiss()
        }
    }

    @ViewBuilder
    private func endedCard(_ title: String) -> some View {
        ContentUnavailableView(
            title,
            systemImage: "hand.raised.slash"
        )
        .task {
            try? await Task.sleep(for: .seconds(2))

            guard !Task.isCancelled else { return }

            dismiss()
        }
    }

    // MARK: - Body

    @ViewBuilder
    private var content: some View {
        switch stage {
        case .voting:
            if let displayedPoll {
                ballot(displayedPoll)
            }

        case let .closed(winnerOptionID):
            if let displayedPoll {
                winnerCard(displayedPoll, winnerOptionID: winnerOptionID)
            }

        case .cancelled:
            endedCard(L10n.CouchVote.voteCancelled)

        case .ended:
            // Gone before its deadline: the TV cancelled it (or the TV app quit)
            if let displayedPoll, displayedPoll.deadline > .now {
                endedCard(L10n.CouchVote.voteCancelled)
            } else {
                endedCard(L10n.CouchVote.voteEnded)
            }
        }
    }

    var body: some View {
        content
            .animation(.easeInOut(duration: 0.25), value: stage)
            .animation(.easeInOut(duration: 0.2), value: selectedChoice)
            .animation(.easeInOut(duration: 0.2), value: error == nil)
            .onChange(of: participant.poll) { _, newPoll in
                // Keep the last poll for the result / cancelled card; ignore a different poll
                guard let newPoll else { return }

                if displayedPoll == nil || displayedPoll?.id == newPoll.id {
                    displayedPoll = newPoll
                }
            }
            .task(id: displayedPoll?.id) {
                guard let displayedPoll else { return }

                await loadPosters(for: displayedPoll)
            }
    }
}
