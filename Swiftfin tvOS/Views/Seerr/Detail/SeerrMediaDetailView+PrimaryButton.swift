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
    /// otherwise a disabled status (Requested ✓, Available, Unavailable).
    ///
    /// It is one `Button` in every state, so focus stays on it when the state changes,
    /// e.g. Request → Play once the library lookup finds the item.
    /// On a kid-only couch it is a non-focusable caption instead of Request.
    struct PrimaryButton: View {

        enum Kind: Equatable {
            case askAGrownUp
            case available
            case play
            case request
            case requested(by: String?)
            case unavailable

            /// Whether the button can take focus (and is the screen's default focus).
            var isFocusable: Bool {
                switch self {
                case .play, .request:
                    true
                case .askAGrownUp, .available, .requested, .unavailable:
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
        /// Only kids on the couch: no Request button.
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
                return isRequestBlocked ? .askAGrownUp : .request
            }

            switch viewModel.status {
            case .available, .partiallyAvailable:
                return .available
            case .processing, .requested:
                return .requested(by: viewModel.requesterName)
            case .blocklisted, .notRequested:
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

        private var title: String {
            switch kind {
            case .askAGrownUp:
                L10n.SeerrTVDetail.askAGrownUp
            case .available:
                L10n.SeerrDetail.available
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
            case .available, .requested:
                "checkmark"
            case .play:
                "play.fill"
            case .request:
                "plus"
            case .unavailable:
                "nosign"
            }
        }

        private func perform() {
            switch kind {
            case .play:
                if let libraryItem = viewModel.libraryItem {
                    onPlay(libraryItem)
                }

            case .request:
                // Not `.disabled` while busy: that would throw focus off the button.
                guard !isRequestBusy else { return }

                onRequest()

            case .askAGrownUp, .available, .requested, .unavailable:
                break
            }
        }

        // MARK: - Views

        @ViewBuilder
        private var icon: some View {
            if kind == .request, isRequestBusy {
                ProgressView()
            } else {
                Image(systemName: systemImage)
            }
        }

        /// A kid-only couch: a caption in the button's place, not focusable.
        @ViewBuilder
        private var caption: some View {
            HStack {
                icon

                Text(title)
                    .lineLimit(1)
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
                .glassEffect(
                    .regular.selection(
                        tint: accentColor,
                        foregroundColor: accentColor.overlayColor
                    ),
                    in: .capsule
                )
            }
            .buttonBorderShape(.capsule)
            .buttonStyle(BasicHoverButtonStyle())
            .focused(focus, equals: .primary)
            .disabled(!kind.isFocusable)
            .frame(height: 75)
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                if kind == .askAGrownUp {
                    caption
                } else {
                    button
                }

                if kind == .request, let requestingAsName {
                    Text(L10n.SeerrTVDetail.requestingAs(requestingAsName))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}
