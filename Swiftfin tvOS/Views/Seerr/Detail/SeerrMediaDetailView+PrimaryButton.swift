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

extension SeerrMediaDetailView {

    /// The 75 pt capsule at the top of the left column, styled like `PlayButton`:
    /// Play when the title is in the library, Request when it can be requested,
    /// otherwise a status (Requested ✓, Available, Unavailable).
    ///
    /// It is one `Button` in every state, so focus stays on it when the state changes,
    /// e.g. Request → Requested ✓ after a request, or Request → Play once the library lookup finds the item.
    /// Statuses are focusable no-ops for the same reason.
    ///
    /// When the couch may not request (`SeerrMediaDetailViewModel.requestGate`):
    /// - only restricted members: "Ask a grown-up", which saves the title for the kids ("Asked ✓");
    /// - a child and a title above kid level: a non-focusable "Not while Tuur is on the couch" caption.
    struct PrimaryButton: View {

        enum Kind: Equatable {
            case askAGrownUp
            case asked
            case available
            case notWithChild
            case play
            case request
            case requested(by: String?)
            case unavailable

            /// Whether the button can take focus (and is the screen's default focus).
            var isFocusable: Bool {
                switch self {
                case .askAGrownUp, .asked, .available, .play, .request, .requested:
                    true
                case .notWithChild, .unavailable:
                    false
                }
            }

            /// Whether pressing it does something: the accent-tinted style.
            var isProminent: Bool {
                switch self {
                case .askAGrownUp, .play, .request:
                    true
                case .asked, .available, .notWithChild, .requested, .unavailable:
                    false
                }
            }
        }

        @Default(.accentColor)
        private var accentColor

        @ObservedObject
        var viewModel: SeerrMediaDetailViewModel

        let focus: FocusState<FocusTarget?>.Binding
        /// The requester's name when it isn't the primary user ("Requesting as Sam").
        let requestingAsName: String?
        /// The couch may not request this title (`requestGate` isn't `.allowed`).
        let isRequestBlocked: Bool
        /// The person being signed in to Seerr before the request, if any.
        let signingInName: String?
        let onPlay: (BaseItemDto) -> Void
        let onRequest: () -> Void

        static func kind(
            for viewModel: SeerrMediaDetailViewModel,
            isRequestBlocked: Bool
        ) -> Kind {
            if viewModel.libraryItem != nil {
                return .play
            }

            if viewModel.canRequest {
                guard isRequestBlocked else { return .request }

                switch viewModel.requestGate {
                case .allowed, .askAGrownUp:
                    return viewModel.hasAskedAGrownUp ? .asked : .askAGrownUp
                case .notWithChild:
                    return .notWithChild
                }
            }

            switch viewModel.status {
            case .available, .partiallyAvailable:
                return .available
            case .processing, .requested:
                return .requested(by: viewModel.requesterName)
            case .blocklisted, .declined, .notRequested:
                return .unavailable
            }
        }

        private var kind: Kind {
            Self.kind(for: viewModel, isRequestBlocked: isRequestBlocked)
        }

        /// Requesting, signing in first, or still checking whether the title is in the library.
        private var isRequestBusy: Bool {
            viewModel.background.is(.requesting) ||
                signingInName != nil ||
                viewModel.isLookingUpLibraryItem
        }

        private var isUpdatingAudience: Bool {
            viewModel.background.is(.updatingAudience)
        }

        private var isBusy: Bool {
            switch kind {
            case .request:
                isRequestBusy
            case .askAGrownUp:
                isUpdatingAudience
            case .asked, .available, .notWithChild, .play, .requested, .unavailable:
                false
            }
        }

        private var title: String {
            switch kind {
            case .askAGrownUp:
                L10n.SeerrDetail.askAGrownUp
            case .asked:
                L10n.SeerrDetail.asked
            case .available:
                L10n.SeerrDetail.available
            case .notWithChild:
                viewModel.notWithChildMessage
            case .play:
                L10n.play
            case .request:
                signingInName.map(L10n.SeerrTVDetail.signingIn) ?? L10n.SeerrDetail.request
            case let .requested(requesterName):
                requesterName.map(L10n.SeerrDetail.requestedBy) ?? L10n.SeerrDetail.requested
            case .unavailable:
                L10n.SeerrDetail.unavailable
            }
        }

        private var systemImage: String {
            switch kind {
            case .askAGrownUp:
                "figure.child"
            case .asked:
                "hand.raised.fill"
            case .available, .requested:
                "checkmark"
            case .notWithChild:
                "hand.raised.slash.fill"
            case .play:
                "play.fill"
            case .request:
                "plus"
            case .unavailable:
                "nosign"
            }
        }

        /// The line under the button: who the request goes (or went) out as, or the "asked" confirmation.
        private var footnote: String? {
            switch kind {
            case .request:
                requestingAsName.map(L10n.SeerrTVDetail.requestingAs)
            case .requested:
                viewModel.requestedAsName.map(L10n.SeerrTVDetail.requestedAs)
            case .asked:
                L10n.SeerrDetail.askedConfirmation
            case .askAGrownUp, .available, .notWithChild, .play, .unavailable:
                nil
            }
        }

        private var glass: BackportGlass {
            if kind.isProminent {
                return BackportGlass.regular.selection(
                    tint: accentColor,
                    foregroundColor: accentColor.overlayColor
                )
            }

            return BackportGlass.regular.selection(
                tint: Color.gray.opacity(0.3),
                foregroundColor: Color.primary
            )
        }

        private func perform() {
            // Not `.disabled` while busy: that would throw focus off the button.
            guard !isBusy else { return }

            switch kind {
            case .play:
                if let libraryItem = viewModel.libraryItem {
                    onPlay(libraryItem)
                }

            case .request:
                onRequest()

            case .askAGrownUp:
                viewModel.saveForAGrownUp()

            // Focusable no-ops, so focus stays on the button
            case .asked, .available, .notWithChild, .requested, .unavailable:
                break
            }
        }

        // MARK: - Views

        @ViewBuilder
        private var icon: some View {
            if isBusy {
                ProgressView()
            } else {
                Image(systemName: systemImage)
            }
        }

        /// A child on the couch and a title above kid level: a caption in the button's place, not focusable.
        @ViewBuilder
        private var caption: some View {
            HStack {
                icon

                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .font(.callout)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 75)
            .background(Color.gray.opacity(0.15), in: .capsule)
            .accessibilityElement(children: .combine)
        }

        @ViewBuilder
        private var button: some View {
            Button(action: perform) {
                HStack {
                    icon

                    Text(title)
                        .lineLimit(1)
                }
                .font(.callout)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .backport
                .glassEffect(glass, in: .capsule)
            }
            .buttonBorderShape(.capsule)
            .buttonStyle(BasicHoverButtonStyle())
            .focused(focus, equals: .primary)
            .disabled(!kind.isFocusable)
            .frame(height: 75)
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                if kind == .notWithChild {
                    caption
                } else {
                    button
                }

                if let footnote {
                    Text(footnote)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }
}
