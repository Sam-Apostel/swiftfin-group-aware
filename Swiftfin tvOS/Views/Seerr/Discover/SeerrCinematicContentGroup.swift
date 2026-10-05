//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

/// The Discover hero: a full-height cinematic selector of landscape backdrops,
/// with the focused title's name, year, type, rating and Seerr status above it.
struct SeerrCinematicContentGroup: ContentGroup {

    let id: String = "seerr-hero"
    let items: [SeerrMedia]

    var _shouldBeResolved: Bool {
        items.isNotEmpty
    }

    func body(with viewModel: Empty) -> some View {
        HeroView(items: items)
    }

    // MARK: - Hero

    private struct HeroView: View {

        @Router
        private var router

        let items: [SeerrMedia]

        var body: some View {
            CinematicItemSelector(
                items: items
            ) { media in
                router.route(to: .seerrMedia(mediaType: media.mediaType, tmdbID: media.id))
            } topContent: { media in
                TopContent(media: media)
            }
            .preference(
                key: ContentGroupCustomizationKey.self,
                value: .ignoreSafeAreaTop
            )
        }
    }

    // MARK: - Top Content

    private struct TopContent: View {

        let media: SeerrMedia

        /// The status capsule: only for titles Seerr knows about.
        private var status: SeerrMediaDetailStatus? {
            switch media.status {
            case .available:
                .available
            case .partiallyAvailable:
                .partiallyAvailable
            case .pending:
                .requested
            case .processing:
                .processing
            case .unknown, .blocklisted, .deleted:
                nil
            }
        }

        private var mediaTypeTitle: String {
            switch media.mediaType {
            case .movie:
                L10n.SeerrTV.movie
            case .tv:
                L10n.SeerrTV.show
            }
        }

        private var rating: Double? {
            guard let voteAverage = media.voteAverage, voteAverage > 0 else { return nil }

            return voteAverage
        }

        @ViewBuilder
        private var metadata: some View {
            DotHStack {
                if let year = media.year {
                    Text(String(year))
                }

                Text(mediaTypeTitle)

                if let rating {
                    Text(L10n.SeerrTV.rating(rating))
                }
            }
            .font(.callout)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
        }

        @ViewBuilder
        private func statusCapsule(_ status: SeerrMediaDetailStatus) -> some View {
            Label(status.displayTitle, systemImage: status.systemImage)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(status.color)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(status.color.opacity(0.2), in: .capsule)
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text(media.displayTitle)
                    .font(.largeTitle)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                metadata

                if let status {
                    statusCapsule(status)
                }
            }
            .frame(maxWidth: 1100, alignment: .leading)
            .edgePadding(.leading)
        }
    }
}
