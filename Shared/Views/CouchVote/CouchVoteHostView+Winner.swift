//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import JellyfinAPI
import SwiftUI

// MARK: - WinnerReveal

extension CouchVoteHostView {

    /// The reveal after the vote closes: the slot reel spins through the options
    /// (only the tied ones after a tie), lands on the winner, then "Tonight: …" + Watch.
    struct WinnerReveal: View {

        @Default(.accentColor)
        private var accentColor

        let options: [CouchVoteOption]
        let items: [String: BaseItemDto]
        let winnerOptionID: String?
        let tiedOptionIDs: [String]
        let winnerVoters: [UserState]
        let winnerVoteCount: Int
        let server: ServerState
        let hasLanded: Bool
        let isResolvingPlayback: Bool
        let focusedField: FocusState<FocusField?>.Binding
        let onLanded: () -> Void
        let onWatch: () -> Void
        let onBack: () -> Void

        private var winner: CouchVoteOption? {
            winnerOptionID.flatMap { id in
                options.first { $0.id == id }
            }
        }

        private var wasTie: Bool {
            tiedOptionIDs.count > 1 && winnerVoteCount > 0
        }

        /// The posters the reel spins through, in option order.
        private var reelItems: [BaseItemDto] {
            let ids: [String] = wasTie
                ? options.map(\.id).filter { tiedOptionIDs.contains($0) }
                : options.map(\.id)

            return ids.compactMap { items[$0] }
        }

        private var canSpin: Bool {
            guard let winnerOptionID, items[winnerOptionID] != nil else { return false }

            return reelItems.count > 1
        }

        private var posterWidth: CGFloat {
            UIDevice.isTV ? 360 : 200
        }

        // MARK: - Reel

        @ViewBuilder
        private var reel: some View {
            if canSpin {
                CouchDeciderSlotReel(
                    items: reelItems,
                    landingItemID: winnerOptionID,
                    spinID: 1,
                    onLanded: onLanded
                )
            } else if let winnerOptionID, let item = items[winnerOptionID] {
                PosterImage(
                    item: item,
                    type: .portrait,
                    size: .medium
                )
                .onAppear(perform: onLanded)
            } else {
                ZStack {
                    Rectangle()
                        .fill(.complexSecondary)

                    SystemImageContentView(systemName: "film")
                }
                .posterStyle(.portrait)
                .onAppear(perform: onLanded)
            }
        }

        // MARK: - Title

        @ViewBuilder
        private var title: some View {
            VStack(spacing: UIDevice.isTV ? 16 : 8) {
                if let winner {
                    Text(L10n.CouchVote.tonight(winner.title))
                        .font(UIDevice.isTV ? .title2 : .title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)

                    if let subtitle = winner.subtitle {
                        Text(subtitle)
                            .font(UIDevice.isTV ? .callout : .subheadline)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 12) {
                        if winnerVoters.isNotEmpty {
                            CouchAvatarStack(
                                users: winnerVoters,
                                server: server,
                                size: UIDevice.isTV ? 44 : 28
                            )
                        }

                        Text(L10n.CouchVote.voteCount(winnerVoteCount))
                            .font(UIDevice.isTV ? .headline : .subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(accentColor)
                    }

                    if wasTie {
                        Text(L10n.CouchVote.tieBreak)
                            .font(UIDevice.isTV ? .caption : .footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(L10n.CouchVote.noWinner)
                        .font(.title3)
                        .fontWeight(.semibold)
                }
            }
            .scaleEffect(hasLanded ? 1 : 0.6)
            .opacity(hasLanded ? 1 : 0)
        }

        // MARK: - Buttons

        @ViewBuilder
        private var watchButton: some View {
            Button(action: onWatch) {
                HStack(spacing: 10) {
                    if isResolvingPlayback {
                        ProgressView()
                    } else {
                        Image(systemName: "play.fill")
                    }

                    Text(L10n.CouchVote.watch)
                }
                .frame(maxWidth: .infinity)
            }
            .fontWeight(.semibold)
            .backport
            .buttonStyle(.glassProminent.shadow(false))
            .tint(accentColor)
            #if os(iOS)
            .controlSize(.large)
            #endif
            .frame(height: UIDevice.isTV ? 75 : 50)
            .frame(maxWidth: UIDevice.isTV ? 450 : .infinity)
            .focused(focusedField, equals: .watch)
            .disabled(winner == nil || isResolvingPlayback)
        }

        @ViewBuilder
        private var backButton: some View {
            Button(action: onBack) {
                Label(L10n.CouchVote.backToDecider, systemImage: "dice.fill")
                    .frame(maxWidth: .infinity)
            }
            .fontWeight(.semibold)
            .backport
            .buttonStyle(.glass)
            #if os(iOS)
            .controlSize(.large)
            #endif
            .frame(height: UIDevice.isTV ? 75 : 50)
            .frame(maxWidth: UIDevice.isTV ? 450 : .infinity)
        }

        @ViewBuilder
        private var buttons: some View {
            HStack(spacing: UIDevice.isTV ? 40 : 12) {
                watchButton

                backButton
            }
            .focusSection()
            .opacity(hasLanded ? 1 : 0)
            .disabled(!hasLanded)
        }

        var body: some View {
            VStack(spacing: UIDevice.isTV ? 40 : 20) {
                reel
                    .frame(width: posterWidth)
                    .shadow(radius: 20)
                    .scaleEffect(hasLanded ? 1.04 : 1)

                title

                buttons
                    .frame(maxWidth: 600)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
