//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

extension SeerrMediaDetailView {

    /// Mirrors the tvOS branch of `ItemView.RegularEnhancedHeaderContentGroup`:
    /// a 450 pt left column with the title and the buttons, and a right column
    /// with the status, attributes, genres, overview and cast, bottom-aligned.
    struct Header: View {

        @FocusState
        private var focus: FocusTarget?

        @ObservedObject
        var viewModel: SeerrMediaDetailViewModel

        let details: SeerrMediaDetails
        /// The requester's name when it isn't the primary user ("Requesting as Sam").
        let requestingAsName: String?
        /// Only kids on the couch: no Request button.
        let isRequestBlocked: Bool
        /// The person being signed in to Seerr before a request, if any.
        let signingInName: String?
        let onPlay: (BaseItemDto) -> Void
        let onRequest: () -> Void
        let onWhoIsItFor: () -> Void

        /// The primary button, unless it can't take focus (a status, or the kid caption).
        private var defaultFocusTarget: FocusTarget {
            let kind = PrimaryButton.kind(for: viewModel, isRequestBlocked: isRequestBlocked)

            return kind.isFocusable ? .primary : .audience
        }

        /// A partially available show can be played and still have seasons left to request.
        private var showsRequestMore: Bool {
            viewModel.libraryItem != nil && viewModel.canRequest && !isRequestBlocked
        }

        private var isRequestBusy: Bool {
            viewModel.background.is(.requesting) || signingInName != nil
        }

        private var isUpdatingAudience: Bool {
            viewModel.background.is(.updatingAudience)
        }

        // MARK: - Left Column

        @ViewBuilder
        private var titleView: some View {
            VStack(alignment: .leading, spacing: 10) {
                Text(details.title)
                    .fixedSize(horizontal: false, vertical: true)
                    .font(.largeTitle)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)

                if let tagline = details.tagline?.nilIfBlank {
                    Text(tagline)
                        .font(.callout)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private func secondaryButton(
            title: String,
            systemImage: String,
            isLoading: Bool,
            focusTarget: FocusTarget,
            action: @escaping () -> Void
        ) -> some View {
            Button {
                // Not `.disabled` while busy: that would throw focus off the button.
                guard !isLoading else { return }

                action()
            } label: {
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
                .glassEffect(.regular, in: .capsule)
            }
            .buttonBorderShape(.capsule)
            .buttonStyle(BasicHoverButtonStyle())
            .foregroundStyle(.primary, .secondary)
            .focused($focus, equals: focusTarget)
            .frame(height: 75)
        }

        @ViewBuilder
        private var audienceButton: some View {
            secondaryButton(
                title: L10n.SeerrDetail.whosItFor,
                systemImage: viewModel.watchlistEntry == nil ? "bookmark" : "bookmark.fill",
                isLoading: isUpdatingAudience,
                focusTarget: .audience,
                action: onWhoIsItFor
            )
            .isSelected(viewModel.watchlistEntry != nil)
        }

        @ViewBuilder
        private var buttons: some View {
            VStack(alignment: .leading, spacing: 24) {
                PrimaryButton(
                    viewModel: viewModel,
                    focus: $focus,
                    requestingAsName: requestingAsName,
                    isRequestBlocked: isRequestBlocked,
                    signingInName: signingInName,
                    onPlay: onPlay,
                    onRequest: onRequest
                )

                if showsRequestMore {
                    secondaryButton(
                        title: L10n.SeerrDetail.requestMoreSeasons,
                        systemImage: "plus",
                        isLoading: isRequestBusy,
                        focusTarget: .requestMore,
                        action: onRequest
                    )
                }

                audienceButton

                if let audience = viewModel.watchlistEntry?.audience, audience.isNotEmpty {
                    AudienceLabel(
                        audience: audience,
                        users: viewModel.householdUsers
                    )
                }
            }
            .focusSection()
            .defaultFocus($focus, defaultFocusTarget, priority: .userInitiated)
        }

        @ViewBuilder
        private var leftColumn: some View {
            VStack(alignment: .leading, spacing: 30) {
                titleView

                buttons
            }
            .frame(width: 450)
        }

        // MARK: - Right Column

        @ViewBuilder
        private var statusRow: some View {
            let status = viewModel.status

            HStack(spacing: 20) {
                Label(status.displayTitle, systemImage: status.systemImage)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(status.color)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(status.color.opacity(0.2), in: .capsule)

                if viewModel.isLookingUpLibraryItem {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 40, height: 40)
                }
            }
        }

        private var ratingText: String? {
            guard let voteAverage = details.voteAverage, voteAverage > 0 else { return nil }

            return voteAverage.formatted(.number.precision(.fractionLength(1)))
        }

        @ViewBuilder
        private var attributes: some View {
            DotHStack {
                if let year = details.year {
                    Text(String(year))
                }

                if details.mediaType == .movie, let runtimeMinutes = details.runtimeMinutes, runtimeMinutes > 0 {
                    Text(Duration.seconds(runtimeMinutes * 60), format: .hourMinuteAbbreviated)
                }

                if details.mediaType == .tv, let numberOfSeasons = details.numberOfSeasons, numberOfSeasons > 0 {
                    Text(L10n.SeerrDetail.seasonCount(numberOfSeasons))
                }

                if let ratingText {
                    Label {
                        Text(ratingText)
                    } icon: {
                        Image(systemName: "star.fill")
                    }
                    .labelStyle(.attributeBadgeOutline)
                }

                if let certification = details.certification, certification.isNotEmpty {
                    EmptyLabel(certification)
                        .labelStyle(.attributeBadgeOutline)
                }
            }
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
        }

        @ViewBuilder
        private var genres: some View {
            if details.genres.isNotEmpty {
                Text(details.genres.prefix(3).map(\.name).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }

        @ViewBuilder
        private var overview: some View {
            if let overview = details.overview?.nilIfBlank {
                Text(overview)
                    .font(.footnote)
                    .lineLimit(6)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        @ViewBuilder
        private var starring: some View {
            let names = details.cast.prefix(4).map(\.name)

            if names.isNotEmpty {
                Text(L10n.SeerrTVDetail.starring(names.joined(separator: ", ")))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }

        @ViewBuilder
        private var rightColumn: some View {
            VStack(alignment: .leading, spacing: 16) {
                statusRow

                attributes

                genres

                overview

                starring
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        // MARK: - Body

        var body: some View {
            HStack(alignment: .bottom, spacing: EdgeInsets.edgePadding) {
                leftColumn

                rightColumn
            }
            .focusSection()
        }
    }
}
