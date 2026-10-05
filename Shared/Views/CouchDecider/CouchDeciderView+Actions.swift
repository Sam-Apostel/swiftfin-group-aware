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
import SwiftUI

extension CouchDeciderView {

    /// The focusable buttons of the action bar.
    ///
    /// To add a button (e.g. phone voting): add a case here, a button in `ActionBar.body`,
    /// and a closure for it.
    enum DeciderAction: Hashable {
        case notTonight
        case shuffle
        case watch
        case details
        case vote
    }

    /// Not tonight · Shuffle · **Watch** · Details.
    ///
    /// On tvOS this is a `.focusSection()` with Watch as its default focus. The buttons are never
    /// disabled, so focus stays on Shuffle / Not tonight while they are clicked repeatedly.
    struct ActionBar: View {

        @Default(.accentColor)
        private var accentColor

        let isResolving: Bool
        let focusedAction: FocusState<DeciderAction?>.Binding
        let onNotTonight: () -> Void
        let onShuffle: () -> Void
        let onWatch: () -> Void
        let onDetails: () -> Void
        /// "Let everyone vote" (#33). `nil` hides the button (solo couch, fewer than 3 matches).
        var onVote: (() -> Void)?

        var body: some View {
            #if os(tvOS)
            // The vote button gets its own row: five labelled buttons don't fit next to the poster
            VStack(alignment: .leading, spacing: 30) {
                buttonRow

                if let onVote {
                    voteButton(onVote)
                }
            }
            .focusSection()
            .defaultFocus(focusedAction, DeciderAction.watch, priority: .userInitiated)
            #else
            buttonRow
                .focusSection()
                .defaultFocus(focusedAction, DeciderAction.watch, priority: .userInitiated)
            #endif
        }

        private var buttonRow: some View {
            HStack(spacing: UIDevice.isTV ? 30 : 12) {
                secondaryButton(
                    L10n.CouchDecider.notTonight,
                    systemImage: "hand.thumbsdown",
                    action: .notTonight,
                    perform: onNotTonight
                )

                secondaryButton(
                    L10n.CouchDecider.shuffle,
                    systemImage: "shuffle",
                    action: .shuffle,
                    perform: onShuffle
                )

                watchButton

                secondaryButton(
                    L10n.details,
                    systemImage: "info.circle",
                    action: .details,
                    perform: onDetails
                )

                #if os(iOS)
                if let onVote {
                    voteButton(onVote)
                }
                #endif
            }
        }

        // MARK: - Vote

        @ViewBuilder
        private func voteButton(_ onVote: @escaping () -> Void) -> some View {
            secondaryButton(
                L10n.CouchVote.letEveryoneVote,
                systemImage: "hand.raised.fill",
                action: .vote,
                perform: onVote
            )
        }

        // MARK: - Watch

        private var watchLabel: some View {
            HStack(spacing: UIDevice.isTV ? 16 : 8) {
                if isResolving {
                    ProgressView()
                } else {
                    Image(systemName: "play.fill")
                }

                Text(L10n.CouchDecider.watch)
                    .lineLimit(1)
            }
        }

        /// tvOS: the system prominent button, so the focus engine and `.focused` see it directly.
        @ViewBuilder
        private var watchButton: some View {
            #if os(tvOS)
            Button(action: onWatch) {
                watchLabel
                    .frame(minWidth: 260)
            }
            .fontWeight(.semibold)
            .buttonStyle(.borderedProminent)
            .tint(accentColor)
            .focused(focusedAction, equals: DeciderAction.watch)
            .accessibilityLabel(L10n.CouchDecider.watch)
            #else
            Button(action: onWatch) {
                watchLabel
                    .frame(maxWidth: .infinity)
            }
            .fontWeight(.semibold)
            .backport
            .buttonStyle(.glassProminent.shadow(false))
            .tint(accentColor)
            .controlSize(.large)
            .frame(height: 54)
            .focused(focusedAction, equals: DeciderAction.watch)
            .accessibilityLabel(L10n.CouchDecider.watch)
            #endif
        }

        // MARK: - Secondary

        @ViewBuilder
        private func secondaryButton(
            _ title: String,
            systemImage: String,
            action: DeciderAction,
            perform: @escaping () -> Void
        ) -> some View {
            #if os(tvOS)
            Button(action: perform) {
                Label(title, systemImage: systemImage)
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }
            .focused(focusedAction, equals: action)
            #else
            Button(action: perform) {
                Label(title, systemImage: systemImage)
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .frame(width: 54, height: 54)
            }
            .foregroundStyle(.primary, .secondary)
            .buttonStyle(.borderless)
            .buttonBorderShape(.circle)
            .backport
            .glassEffect(.regular.interactive(), in: .circle)
            .focused(focusedAction, equals: action)
            .accessibilityLabel(title)
            #endif
        }
    }
}

// MARK: - Vote (#33)

extension CouchDeciderView {

    /// "Let everyone vote" shows for a group couch with at least 3 matching titles.
    @MainActor
    static func isVoteAvailable(_ viewModel: CouchDeciderViewModel) -> Bool {
        viewModel.couch.isGroup && viewModel.matchingCount >= 3
    }

    /// The vote screen for the current card and the next ones (up to 5; the screen picks 3, 4 or 5).
    ///
    /// Near the end of a lap the deck has fewer upcoming cards, so it tops up
    /// with other matching titles in pool order.
    @MainActor
    static func voteRoute(_ viewModel: CouchDeciderViewModel) -> NavigationRoute? {
        let maxCount = 5
        var candidates = viewModel.upcomingCandidates(maxCount)

        if candidates.count < maxCount {
            let excluded = Container.shared.couchDeciderExclusions().excluded(couchID: viewModel.couch.id)

            for candidate in viewModel.pool.candidates where candidates.count < maxCount {
                guard !candidates.contains(where: { $0.id == candidate.id }),
                      !excluded.contains(candidate.id),
                      viewModel.filters.matches(candidate)
                else { continue }

                candidates.append(candidate)
            }
        }

        guard candidates.count >= 2 else { return nil }

        var items: [String: BaseItemDto] = [:]
        for candidate in candidates {
            items[candidate.id] = viewModel.item(for: candidate.id)
        }

        return .couchVote(
            couch: viewModel.couch,
            candidates: candidates,
            items: items
        )
    }
}
