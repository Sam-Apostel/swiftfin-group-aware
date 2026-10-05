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

extension WatchlistsView {

    struct EntryRow: View {

        @Default(.accentColor)
        private var accentColor

        let entry: AudienceWatchlistEntry
        let libraryItem: BaseItemDto?
        let availability: WatchlistAvailability
        let action: () -> Void
        let onChangeAudience: () -> Void
        let onRemove: () -> Void

        private var kindTitle: String {
            switch entry.kind {
            case .movie:
                L10n.movie
            case .tv:
                L10n.series
            }
        }

        var body: some View {
            Button(action: action) {
                HStack(alignment: .center, spacing: EdgeInsets.edgePadding) {
                    PosterThumbnail(entry: entry, libraryItem: libraryItem)
                        .subtleShadow()
                        .frame(width: 60)

                    details
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .foregroundStyle(.primary, .secondary)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(
                    L10n.Watchlists.remove,
                    systemImage: "trash",
                    role: .destructive,
                    action: onRemove
                )

                Button(
                    L10n.Watchlists.changeWho,
                    systemImage: "person.2",
                    action: onChangeAudience
                )
                .tint(accentColor)
            }
            .contextMenu {
                Button(
                    L10n.Watchlists.changeWho,
                    systemImage: "person.2",
                    action: onChangeAudience
                )

                Button(
                    L10n.Watchlists.remove,
                    systemImage: "trash",
                    role: .destructive,
                    action: onRemove
                )
            }
        }

        @ViewBuilder
        private var details: some View {
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.title)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                DotHStack {
                    if let year = entry.year {
                        Text(String(year))
                    }

                    Text(kindTitle)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                AvailabilityChip(availability: availability)
            }
        }
    }

    // MARK: - Availability chip

    struct AvailabilityChip: View {

        let availability: WatchlistAvailability

        var body: some View {
            Label(availability.displayTitle, systemImage: availability.systemImage)
                .font(.caption2)
                .fontWeight(.semibold)
                .lineLimit(1)
                .foregroundStyle(availability.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(availability.color.opacity(0.15), in: .capsule)
        }
    }

    // MARK: - Poster

    /// TMDB `w185` poster when the entry has one, else the Jellyfin item's own image.
    struct PosterThumbnail: View {

        let entry: AudienceWatchlistEntry
        let libraryItem: BaseItemDto?

        private var systemImage: String {
            switch entry.kind {
            case .movie:
                "film"
            case .tv:
                "tv"
            }
        }

        private var tmdbURL: URL? {
            SeerrImage.url(entry.posterPath, size: "w185")
        }

        var body: some View {
            if let tmdbURL {
                ZStack {
                    Rectangle()
                        .fill(.complexSecondary)

                    ImageView(tmdbURL)
                        .image { (image: Image) in
                            image
                                .aspectRatio(contentMode: .fill)
                        }
                        .placeholder { _ in
                            SystemImageContentView(systemName: systemImage)
                        }
                        .failure {
                            SystemImageContentView(systemName: systemImage)
                        }
                }
                .posterStyle(.portrait)
            } else if let libraryItem {
                PosterImage(
                    item: libraryItem,
                    type: .portrait,
                    size: .extraSmall
                )
            } else {
                ZStack {
                    Rectangle()
                        .fill(.complexSecondary)

                    SystemImageContentView(systemName: systemImage)
                }
                .posterStyle(.portrait)
            }
        }
    }
}
