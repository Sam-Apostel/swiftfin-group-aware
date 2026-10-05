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

// MARK: - OptionList

extension CouchVoteHostView {

    /// The vote options with their live counts.
    ///
    /// - tvOS: one row of large posters (its own focus section).
    /// - iOS: a vertical list.
    struct OptionList: View {

        let options: [CouchVoteOption]
        let items: [String: BaseItemDto]
        let tally: CouchVoteTally
        let isLive: Bool
        let server: ServerState
        let voters: (String) -> [UserState]
        let focusedField: FocusState<FocusField?>.Binding
        let onSelect: (CouchVoteOption) -> Void

        private func isLeading(_ option: CouchVoteOption) -> Bool {
            isLive && tally.count(for: option.id) > 0 && tally.leadingOptionIDs.contains(option.id)
        }

        @ViewBuilder
        private func card(_ option: CouchVoteOption) -> some View {
            OptionCard(
                option: option,
                item: items[option.id],
                count: tally.count(for: option.id),
                voters: voters(option.id),
                isLive: isLive,
                isLeading: isLeading(option),
                server: server
            ) {
                onSelect(option)
            }
            .focused(focusedField, equals: .option(option.id))
        }

        var body: some View {
            #if os(tvOS)
            HStack(alignment: .top, spacing: 40) {
                ForEach(options) { option in
                    card(option)
                        .frame(maxWidth: 340)
                }
            }
            .frame(maxWidth: .infinity)
            .focusSection()
            #else
            VStack(spacing: 10) {
                ForEach(options) { option in
                    card(option)
                }
            }
            .frame(maxWidth: 600)
            #endif
        }
    }
}

// MARK: - OptionCard

extension CouchVoteHostView {

    /// One option: poster, title, subtitle, the live count and who voted for it.
    struct OptionCard: View {

        @Default(.accentColor)
        private var accentColor

        let option: CouchVoteOption
        let item: BaseItemDto?
        let count: Int
        let voters: [UserState]
        let isLive: Bool
        let isLeading: Bool
        let server: ServerState
        let action: () -> Void

        @ViewBuilder
        private var poster: some View {
            if let item {
                PosterImage(
                    item: item,
                    type: .portrait,
                    size: UIDevice.isTV ? .medium : .small
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
        private var titles: some View {
            Text(option.title)
                .font(UIDevice.isTV ? .headline : .callout)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .lineLimit(UIDevice.isTV ? 1 : 2)

            if let subtitle = option.subtitle {
                Text(subtitle)
                    .font(UIDevice.isTV ? .caption : .caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }

        @ViewBuilder
        private var countView: some View {
            Text(count, format: .number)
                .font(.system(size: UIDevice.isTV ? 44 : 26, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isLeading ? AnyShapeStyle(accentColor) : AnyShapeStyle(.primary))
                .contentTransition(.numericText(value: Double(count)))
                .animation(.spring(response: 0.35, dampingFraction: 0.6), value: count)
                .accessibilityLabel(L10n.CouchVote.voteCount(count))
        }

        @ViewBuilder
        private var votersView: some View {
            if voters.isNotEmpty {
                CouchAvatarStack(
                    users: voters,
                    server: server,
                    size: UIDevice.isTV ? 40 : 24
                )
                .transition(.opacity.combined(with: .scale))
            }
        }

        #if os(tvOS)
        var body: some View {
            Button(action: action) {
                VStack(alignment: .leading, spacing: 14) {
                    poster
                        .overlay {
                            if isLeading {
                                Rectangle()
                                    .stroke(accentColor, lineWidth: 8)
                            }
                        }

                    VStack(alignment: .leading, spacing: 4) {
                        titles
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if isLive {
                        HStack(alignment: .center, spacing: 12) {
                            countView

                            Spacer(minLength: 0)

                            votersView
                        }
                        .frame(height: 52)
                    }
                }
                .padding(20)
                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: voters)
            }
            .buttonStyle(.card)
        }
        #else
        var body: some View {
            Button(action: action) {
                HStack(spacing: 12) {
                    poster
                        .frame(width: 60)

                    VStack(alignment: .leading, spacing: 2) {
                        titles
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if isLive {
                        VStack(alignment: .trailing, spacing: 4) {
                            countView

                            votersView
                        }
                    }
                }
                .padding(10)
                .background {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                }
                .overlay {
                    if isLeading {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(accentColor, lineWidth: 2)
                    }
                }
                .contentShape(.rect(cornerRadius: 16))
                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: voters)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary, .secondary)
        }
        #endif
    }
}
