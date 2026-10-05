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

    /// Mirrors `ItemView.CompactEnhancedHeaderContentGroup`: a parallax TMDB backdrop with
    /// the poster, title, metadata, status, actions and overview on a material band.
    struct Header: View {

        @ObservedObject
        var viewModel: SeerrMediaDetailViewModel

        @State
        private var backdropColor: Color = .secondarySystemFill
        @State
        private var isOverviewExpanded = false

        let details: SeerrMediaDetails
        let onPlay: (BaseItemDto) -> Void
        let onRequest: () -> Void
        let onWhoIsItFor: () -> Void

        private let headerAspectRatio = 1.6

        // MARK: - Backdrop

        @ViewBuilder
        private var backdrop: some View {
            MirrorExtensionView(edges: .top) {
                AlternateLayoutView {
                    Color.clear
                } content: {
                    ImageView(SeerrImage.url(details.backdropPath, size: "w1280"))
                        .image { (image: UIImage) in
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .onAppear {
                                    resolveColor(from: image, binding: $backdropColor)
                                }
                        }
                }
                .aspectRatio(headerAspectRatio, contentMode: .fit)
                .accessibilityHidden(true)
            }
            .bottomEdgeGradient(bottomColor: backdropColor)
        }

        private func resolveColor(from image: UIImage, binding: Binding<Color>) {
            Task.detached(priority: .utility) {
                guard let color = image.interestingColor() else { return }

                await MainActor.run {
                    binding.wrappedValue = color
                }
            }
        }

        // MARK: - Poster

        @ViewBuilder
        private var poster: some View {
            ZStack {
                Rectangle()
                    .fill(.complexSecondary)

                AlternateLayoutView {
                    Color.clear
                } content: {
                    ImageView(SeerrImage.url(details.posterPath, size: "w342"))
                        .image { (image: Image) in
                            image
                                .aspectRatio(contentMode: .fill)
                        }
                        .placeholder { _ in
                            Color.clear
                        }
                        .failure {
                            SystemImageContentView(
                                systemName: details.mediaType == .movie ? "film" : "tv"
                            )
                        }
                }
            }
            .posterStyle(.portrait)
            .frame(width: 110)
            .subtleShadow()
            .accessibilityHidden(true)
        }

        // MARK: - Title & Metadata

        @ViewBuilder
        private var title: some View {
            Text(details.title)
                .fixedSize(horizontal: false, vertical: true)
                .font(.largeTitle)
                .fontWeight(.semibold)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
        }

        private var ratingText: String? {
            guard let voteAverage = details.voteAverage, voteAverage > 0 else { return nil }

            return voteAverage.formatted(.number.precision(.fractionLength(1)))
        }

        @ViewBuilder
        private var metadata: some View {
            DotHStack {
                if let year = viewModel.year {
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
        private var statusPill: some View {
            let status = viewModel.status

            Label(status.displayTitle, systemImage: status.systemImage)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(status.color)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(status.color.opacity(0.2), in: .capsule)
        }

        // MARK: - Overview

        @ViewBuilder
        private var overview: some View {
            let tagline = details.tagline?.nilIfBlank
            let overviewText = details.overview?.nilIfBlank

            if tagline != nil || overviewText != nil {
                VStack(alignment: .leading, spacing: 5) {
                    if let tagline {
                        Text(tagline)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                    }

                    if let overviewText {
                        Button {
                            withAnimation(.linear(duration: 0.2)) {
                                isOverviewExpanded.toggle()
                            }
                        } label: {
                            SeeMoreText(overviewText)
                                .font(.footnote)
                                .lineLimit(isOverviewExpanded ? nil : 3)
                                .multilineTextAlignment(.leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        // MARK: - Body

        @ViewBuilder
        private var overlay: some View {
            VStack(alignment: .center, spacing: 10) {
                AlternateLayoutView(alignment: .bottom) {
                    Color.clear
                        .aspectRatio(headerAspectRatio, contentMode: .fit)
                } content: {
                    poster
                }
                .zIndex(10)

                VStack(alignment: .center, spacing: 10) {
                    title

                    metadata

                    genres

                    statusPill

                    ActionButtons(
                        viewModel: viewModel,
                        onPlay: onPlay,
                        onRequest: onRequest,
                        onWhoIsItFor: onWhoIsItFor
                    )
                    .frame(maxWidth: 300)

                    if let audience = viewModel.watchlistEntry?.audience, audience.isNotEmpty {
                        AudienceLabel(
                            audience: audience,
                            users: viewModel.householdUsers
                        )
                    }

                    overview
                }
                .edgePadding(.bottom)
                .background(
                    alignment: .bottom,
                    extendedBy: .init(
                        vertical: 25,
                        horizontal: EdgeInsets.edgePadding
                    )
                ) {
                    Rectangle()
                        .fill(Material.ultraThin)
                        .mask(gradient: .eased(.easeOut)) {
                            (location: 0, opacity: 0)
                            (location: 0.2, opacity: 1)
                        }
                }
                .zIndex(9)
            }
        }

        var body: some View {
            overlay
                .edgePadding(.horizontal)
                .frame(maxWidth: .infinity)
                .colorScheme(.dark)
                .backgroundParallaxHeader(multiplier: 0.3) {
                    backdrop
                }
        }
    }
}
