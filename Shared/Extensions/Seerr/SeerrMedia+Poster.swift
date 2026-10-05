//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import FactoryKit
import SwiftUI

// MARK: - Poster

extension SeerrMedia: Poster {

    var displayTitle: String {
        title
    }

    var subtitle: String? {
        year.map { String($0) }
    }

    var systemImage: String {
        switch mediaType {
        case .movie:
            "film"
        case .tv:
            "tv"
        }
    }

    var preferredPosterDisplayType: PosterDisplayType {
        .portrait
    }

    /// The id of this title in the couch watchlist store (#9).
    var audienceWatchlistEntryID: String {
        AudienceWatchlistEntry.makeID(
            tmdbID: id,
            kind: audienceWatchlistKind,
            jellyfinItemID: nil
        )
    }

    var audienceWatchlistKind: AudienceWatchlistEntry.MediaKind {
        switch mediaType {
        case .movie:
            .movie
        case .tv:
            .tv
        }
    }

    /// TMDB backdrop width for landscape posters: the tvOS hero and focused-poster backgrounds fill a 4K screen.
    private static var landscapeBackdropSize: String {
        #if os(tvOS)
        "w1280"
        #else
        "w780"
        #endif
    }

    func imageSources(
        for displayType: PosterDisplayType,
        environment: Empty
    ) -> [ImageSource] {
        let urls: [URL?] = switch displayType {
        case .landscape:
            [
                SeerrImage.url(backdropPath, size: Self.landscapeBackdropSize),
                SeerrImage.url(posterPath, size: "w342"),
            ]

        case .portrait, .square:
            [SeerrImage.url(posterPath, size: "w342")]
        }

        return urls
            .compactMap(\.self)
            .map { ImageSource(url: $0) }
    }

    func transform(image: Image, displayType: PosterDisplayType) -> some View {
        image
            .aspectRatio(contentMode: .fill)
    }

    var posterLabel: some View {
        SeerrMediaPosterLabel(media: self)
    }

    func posterOverlay(for displayType: PosterDisplayType) -> some View {
        SeerrMediaPosterOverlay(
            media: self,
            displayType: displayType
        )
    }
}

// MARK: - LibraryElement

extension SeerrMedia: LibraryElement {

    static var supportedLibraryStyleOptions: LibraryStyleOptions {
        .init(
            displayTypes: [.grid],
            posterDisplayTypes: [.portrait],
            fallbackPosterDisplayType: .portrait
        )
    }

    func libraryDidSelectElement(
        router: Router.Wrapper,
        in namespace: Namespace.ID
    ) {
        router.route(
            to: .seerrMedia(mediaType: mediaType, tmdbID: id),
            withNamespace: { .push(.zoom(sourceID: "item", namespace: $0)) },
            in: namespace
        )
    }

    func makeBody(
        libraryStyle: LibraryStyle,
        action: (() -> Void)?
    ) -> some View {
        SeerrMediaLibraryGridElement(
            media: self,
            action: action
        )
    }
}

// MARK: - Grid Element

private struct SeerrMediaLibraryGridElement: View {

    @Router
    private var router

    let media: SeerrMedia
    let action: (() -> Void)?

    var body: some View {
        PosterButton(
            item: media,
            displayType: .portrait
        ) { namespace in
            if let action {
                action()
            } else {
                media.libraryDidSelectElement(router: router, in: namespace)
            }
        }
    }
}

// MARK: - Label

/// Mirrors `BaseItemDtoPosterLabel`: title on the first line, year on the second.
private struct SeerrMediaPosterLabel: View {

    let media: SeerrMedia

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(media.displayTitle)
                .font(.footnote)
                .multilineTextAlignment(.leading)
                .lineLimit(1, reservesSpace: true)

            Text(media.subtitle ?? .space)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .lineLimit(1, reservesSpace: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Overlay

/// Corner badges: on a couch watchlist, and the Seerr availability status.
private struct SeerrMediaPosterOverlay: View {

    @Default(.accentColor)
    private var accentColor

    @Environment(\.isSelected)
    private var isSelected

    @InjectedObject(\.audienceWatchlistStore)
    private var watchlistStore

    let media: SeerrMedia
    let displayType: PosterDisplayType

    private var isOnCouchWatchlist: Bool {
        watchlistStore.entry(id: media.audienceWatchlistEntryID) != nil
    }

    @ArrayBuilder<QuadrantItem>
    private var badges: [QuadrantItem] {
        if isOnCouchWatchlist {
            QuadrantItem(color: accentColor) {
                Text(Image(systemName: "sofa.fill"))
                    .accessibilityLabel(L10n.SeerrDiscover.onCouchWatchlist)
            }
        }

        statusBadge
    }

    private var statusBadge: QuadrantItem? {
        switch media.status {
        case .available:
            QuadrantItem(color: .green) {
                Text(Image(systemName: "checkmark"))
                    .fontWeight(.bold)
                    .accessibilityLabel(L10n.SeerrDiscover.available)
            }

        case .partiallyAvailable:
            QuadrantItem(color: .green) {
                Text(Image(systemName: "circle.lefthalf.filled"))
                    .accessibilityLabel(L10n.SeerrDiscover.partiallyAvailable)
            }

        case .pending:
            QuadrantItem(color: .orange) {
                Text(Image(systemName: "hourglass"))
                    .accessibilityLabel(L10n.Seerr.statusPending)
            }

        case .processing:
            QuadrantItem(color: .blue) {
                Text(Image(systemName: "hourglass"))
                    .accessibilityLabel(L10n.Seerr.statusProcessing)
            }

        case .unknown, .blocklisted, .deleted:
            nil
        }
    }

    var body: some View {
        Quadrant(.bottomTrailing) {
            badges
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .opacity(isSelected ? 0.85 : 1)
        .posterCornerRadius(displayType)
    }
}
