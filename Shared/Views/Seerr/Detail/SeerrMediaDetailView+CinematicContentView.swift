//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if os(tvOS)
import JellyfinAPI
import SwiftUI

extension SeerrMediaDetailView {

    /// The tvOS layout, mirroring `ItemView`'s enhanced tvOS header: a full-screen TMDB
    /// backdrop, the title and actions on the left, the overview and status on the right,
    /// and the cast below.
    struct ContentView: View {

        private enum Focus: Hashable {
            case header
            case cast
        }

        @FocusState
        private var focusedSection: Focus?

        @ObservedObject
        var viewModel: SeerrMediaDetailViewModel

        let details: SeerrMediaDetails
        let onPlay: (BaseItemDto) -> Void
        let onRequest: () -> Void
        let onWhoIsItFor: () -> Void

        private var isHeaderFocused: Bool {
            focusedSection == .header
        }

        // MARK: - Background

        /// Like `ItemView.ContentGroupScrollView`: clear behind the header, frosted behind the cast.
        private var background: some View {
            AlternateLayoutView {
                Color.clear
            } content: {
                ImageView(SeerrImage.url(details.backdropPath, size: "w1280"))
                    .failure {
                        Color.black
                    }
                    .aspectRatio(contentMode: .fill)
            }
            .accessibilityHidden(true)
            .overlay {
                Rectangle()
                    .fill(Material.regular)
                    .mask(gradient: .linear) {
                        if isHeaderFocused {
                            (location: 0.3, opacity: 0)
                        } else {
                            (location: 0, opacity: 1)
                        }

                        (location: 1, opacity: 1)
                    }
            }
            .animation(.linear(duration: 0.2), value: isHeaderFocused)
        }

        // MARK: - Header

        private var title: some View {
            Text(details.title)
                .fixedSize(horizontal: false, vertical: true)
                .font(.largeTitle)
                .fontWeight(.semibold)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
        }

        private var overview: some View {
            VStack(alignment: .leading, spacing: 5) {
                if let tagline = details.tagline?.nilIfBlank {
                    Text(tagline)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }

                if let overviewText = details.overview?.nilIfBlank {
                    Text(overviewText)
                        .font(.footnote)
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private var header: some View {
            HStack(alignment: .bottom, spacing: EdgeInsets.edgePadding) {
                VStack(alignment: .leading, spacing: 30) {
                    title

                    ActionButtons(
                        viewModel: viewModel,
                        onPlay: onPlay,
                        onRequest: onRequest,
                        onWhoIsItFor: onWhoIsItFor
                    )

                    if let audience = viewModel.watchlistEntry?.audience, audience.isNotEmpty {
                        AudienceLabel(
                            audience: audience,
                            users: viewModel.householdUsers
                        )
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 450)
                .focusSection()
                .focused($focusedSection, equals: .header)

                VStack(alignment: .leading, spacing: 10) {
                    overview

                    MetadataHStack(details: details, year: viewModel.year)

                    GenresText(details: details)

                    StatusPill(status: viewModel.status)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .edgePadding(.horizontal)
            .frame(maxWidth: .infinity)
            .colorScheme(.dark)
        }

        // MARK: - Body

        var body: some View {
            ZStack {
                background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 50) {
                        CinematicContentGroupContainer {
                            header
                        }

                        if details.cast.isNotEmpty {
                            CastSection(cast: details.cast)
                                .focusSection()
                                .focused($focusedSection, equals: .cast)
                        }
                    }
                    .edgePadding(.bottom)
                }
                .trackingFrame(for: .scrollView)
                .ignoresSafeArea(.container, edges: .all)
                .scrollIndicators(.hidden)
            }
            .defaultFocus($focusedSection, .header, priority: .userInitiated)
        }
    }
}
#endif
