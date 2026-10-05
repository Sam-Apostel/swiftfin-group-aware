//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import SwiftUI

extension View {

    /// Shows the "Vote for tonight" ballot when a TV on the couch starts a vote.
    ///
    /// Attach it once, to a view that stays on screen (the main tab view).
    /// It listens while the app is in the foreground, and never prompts
    /// while the video player is up: the sheet waits until playback stops.
    func couchVotePrompt() -> some View {
        modifier(CouchVotePromptModifier())
    }
}

private struct CouchVotePromptModifier: ViewModifier {

    /// The sheet item. Only the poll id, so that live updates of the poll
    /// (votes, close) don't re-present the sheet.
    private struct PresentedPoll: Identifiable {
        let id: String
    }

    @InjectedObject(\.couchVoteParticipant)
    private var participant

    @State
    private var presentedPoll: PresentedPoll?
    /// Kept after the sheet's binding is cleared, for `onDismiss`.
    @State
    private var lastPresentedPollID: String?
    @State
    private var handledPollIDs: Set<String> = []

    private func presentIfNeeded() {
        guard presentedPoll == nil,
              let poll = participant.poll,
              poll.state == .open,
              !handledPollIDs.contains(poll.id),
              !Container.shared.userSessionManager().hasActivePlayback
        else { return }

        lastPresentedPollID = poll.id
        presentedPoll = PresentedPoll(id: poll.id)
    }

    /// However the sheet went away (swipe, Done, auto-dismiss after the result),
    /// the same poll never prompts again.
    private func onDismiss() {
        if let lastPresentedPollID {
            handledPollIDs.insert(lastPresentedPollID)
        }

        lastPresentedPollID = nil
        participant.dismiss()
    }

    func body(content: Content) -> some View {
        content
            .onAppear {
                participant.startListening()
            }
            .onDisappear {
                participant.stopListening()
            }
            .onScenePhase(.active) {
                participant.startListening()

                Task {
                    await participant.refreshNow()
                }
            }
            .onScenePhase(.background) {
                participant.stopListening()
            }
            .onChange(of: participant.poll) {
                presentIfNeeded()
            }
            .task {
                // Re-check now and then: playback stopping doesn't publish anything,
                // and a prompt held back by the player should show right after it.
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(2))
                    presentIfNeeded()
                }
            }
            .sheet(item: $presentedPoll, onDismiss: onDismiss) { _ in
                CouchVoteBallotView(participant: participant)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
    }
}
