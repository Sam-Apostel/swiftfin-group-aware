//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
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

        var body: some View {
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
            }
            .focusSection()
            .defaultFocus(focusedAction, DeciderAction.watch, priority: .userInitiated)
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
