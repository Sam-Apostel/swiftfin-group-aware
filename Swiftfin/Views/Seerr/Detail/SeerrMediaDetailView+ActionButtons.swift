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

    /// Play / Request / Requested ✓, plus "Who's it for?", styled like `PlayButton` and `ItemActionButtons`.
    struct ActionButtons: View {

        private enum PrimaryAction {
            case available
            case play(BaseItemDto)
            case request
            case requested(by: String?)
            case unavailable
        }

        @Default(.accentColor)
        private var accentColor

        @ObservedObject
        var viewModel: SeerrMediaDetailViewModel

        let onPlay: (BaseItemDto) -> Void
        let onRequest: () -> Void
        let onWhoIsItFor: () -> Void

        private var primaryAction: PrimaryAction {
            if let libraryItem = viewModel.libraryItem {
                return .play(libraryItem)
            }

            if viewModel.canRequest {
                return .request
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

        private var isRequesting: Bool {
            viewModel.background.is(.requesting)
        }

        /// Busy while requesting, or while checking whether the title is already in the library.
        private var isRequestBusy: Bool {
            isRequesting || viewModel.isLookingUpLibraryItem
        }

        private var isUpdatingAudience: Bool {
            viewModel.background.is(.updatingAudience)
        }

        /// A partially available show can be played and still have seasons left to request.
        private var showsRequestMore: Bool {
            viewModel.libraryItem != nil && viewModel.canRequest
        }

        // MARK: - Primary

        @ViewBuilder
        private var primaryButton: some View {
            switch primaryAction {
            case .available:
                capsuleButton(
                    title: L10n.SeerrDetail.available,
                    systemImage: "checkmark",
                    isProminent: false,
                    action: {}
                )
                .disabled(true)

            case let .play(item):
                capsuleButton(
                    title: L10n.play,
                    systemImage: "play.fill",
                    isProminent: true
                ) {
                    onPlay(item)
                }

            case .request:
                capsuleButton(
                    title: L10n.SeerrDetail.request,
                    systemImage: "plus",
                    isProminent: true,
                    isLoading: isRequestBusy,
                    action: onRequest
                )
                .disabled(isRequestBusy)

            case let .requested(requesterName):
                capsuleButton(
                    title: requesterName.map(L10n.SeerrDetail.requestedBy) ?? L10n.SeerrDetail.requested,
                    systemImage: "checkmark",
                    isProminent: false,
                    action: {}
                )
                .disabled(true)

            case .unavailable:
                capsuleButton(
                    title: L10n.SeerrDetail.unavailable,
                    systemImage: "nosign",
                    isProminent: false,
                    action: {}
                )
                .disabled(true)
            }
        }

        // MARK: - Capsule

        private func capsuleButton(
            title: String,
            systemImage: String,
            isProminent: Bool,
            isLoading: Bool = false,
            action: @escaping () -> Void
        ) -> some View {
            let tint: Color = isProminent ? accentColor : .gray.opacity(0.15)
            let foregroundColor: Color = isProminent ? accentColor.overlayColor : .primary

            return Button(action: action) {
                HStack {
                    if isLoading {
                        ProgressView()
                    } else {
                        Image(systemName: systemImage)
                    }

                    Text(title)
                        .lineLimit(1)
                }
                .font(.callout)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .backport
                .glassEffect(
                    .regular.selection(
                        tint: tint,
                        foregroundColor: foregroundColor
                    ),
                    in: .capsule
                )
            }
            .buttonBorderShape(.capsule)
            .buttonStyle(BasicHoverButtonStyle())
            .foregroundStyle(.primary, .secondary)
            .frame(height: 44)
        }

        // MARK: - Body

        var body: some View {
            VStack(spacing: 8) {
                primaryButton

                if showsRequestMore {
                    capsuleButton(
                        title: L10n.SeerrDetail.requestMoreSeasons,
                        systemImage: "plus",
                        isProminent: false,
                        isLoading: isRequesting,
                        action: onRequest
                    )
                    .disabled(isRequesting)
                }

                capsuleButton(
                    title: L10n.SeerrDetail.whosItFor,
                    systemImage: viewModel.watchlistEntry == nil ? "person.badge.plus" : "person.2.fill",
                    isProminent: false,
                    isLoading: isUpdatingAudience,
                    action: onWhoIsItFor
                )
                .disabled(isUpdatingAudience)
            }
        }
    }
}
