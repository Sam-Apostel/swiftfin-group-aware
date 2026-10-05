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

extension CouchDeciderView {

    // MARK: - Poster

    /// The card's large portrait poster. Same frame and corners as `CouchDeciderSlotReel`,
    /// so the reel lands seamlessly on it.
    struct CardPoster: View {

        let item: BaseItemDto

        var body: some View {
            PosterImage(item: item, type: .portrait, size: .medium)
                .aspectRatio(2 / 3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: CouchDeciderSlotReel.cornerRadius, style: .continuous))
                .accessibilityHidden(true)
        }
    }

    // MARK: - Info

    /// Title, `year · runtime` (or `S2 · E5 · 42m`), genres, overview and the "why" tags.
    struct CardInfo: View {

        let candidate: CouchDeciderCandidate
        let item: BaseItemDto?
        /// `false` on a solo couch: the why-tags read "Next up" and "New for you".
        var isGroup: Bool = true

        private var alignment: HorizontalAlignment {
            UIDevice.isTV ? .leading : .center
        }

        private var textAlignment: TextAlignment {
            UIDevice.isTV ? .leading : .center
        }

        private var title: String {
            if candidate.kind == .episode, let seriesName = item?.seriesName {
                return seriesName
            }

            return candidate.title
        }

        /// The episode's own name, under the series title.
        private var episodeTitle: String? {
            guard candidate.kind == .episode else { return nil }

            return item?.name?.nilIfBlank
        }

        private var runtimeLabel: String? {
            if let label = item?.runTimeLabel, (item?.runTimeTicks ?? 0) > 0 {
                return label
            }

            guard let runtime = candidate.runtime, runtime > 0 else { return nil }

            return Duration.seconds(runtime)
                .formatted(.units(allowed: [.hours, .minutes], width: .narrow))
        }

        private var genres: [String] {
            Array(candidate.genres.prefix(3))
        }

        private var overview: String? {
            item?.overview?.nilIfBlank
        }

        var body: some View {
            VStack(alignment: alignment, spacing: UIDevice.isTV ? 16 : 6) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                if let episodeTitle {
                    Text(episodeTitle)
                        .font(UIDevice.isTV ? .headline : .subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                detailsLine

                if let overview {
                    Text(overview)
                        .font(UIDevice.isTV ? .callout : .footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                WhyTags(sources: candidate.sources, isGroup: isGroup)
            }
            .multilineTextAlignment(textAlignment)
            .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
            .accessibilityElement(children: .combine)
        }

        @ViewBuilder
        private var detailsLine: some View {
            DotHStack {
                if candidate.kind == .episode {
                    if let season = item?.parentIndexNumber {
                        Text(L10n.CouchDecider.seasonShort(season))
                    }

                    if let episode = item?.indexNumber {
                        Text(L10n.CouchDecider.episodeShort(episode))
                    }
                } else if let year = candidate.year {
                    Text(String(year))
                }

                if let runtimeLabel {
                    Text(runtimeLabel)
                }

                ForEach(genres, id: \.self) { genre in
                    Text(genre)
                }
            }
            .font(UIDevice.isTV ? .callout : .subheadline)
            .fontWeight(.medium)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }

    // MARK: - Why Tags

    /// Why this card is in the deck: "Picked for this couch", "Next up together", "New for all of you",
    /// "From your library". On a solo couch: "Picked for you", "Next up", "New for you".
    ///
    /// The tags wrap into a column when they don't fit on one line (large text sizes).
    struct WhyTags: View {

        @Default(.accentColor)
        private var accentColor

        let sources: Set<CouchDeciderCandidate.Source>
        var isGroup: Bool = true

        private var orderedSources: [CouchDeciderCandidate.Source] {
            CouchDeciderCandidate.Source.allCases.filter { sources.contains($0) }
        }

        private var spacing: CGFloat {
            UIDevice.isTV ? 16 : 6
        }

        private var columnAlignment: HorizontalAlignment {
            UIDevice.isTV ? .leading : .center
        }

        var body: some View {
            if orderedSources.isNotEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: spacing) {
                        tags
                    }

                    VStack(alignment: columnAlignment, spacing: spacing) {
                        tags
                    }
                }
            }
        }

        private var tags: some View {
            ForEach(orderedSources, id: \.self) { source in
                tag(for: source)
            }
        }

        private func tag(for source: CouchDeciderCandidate.Source) -> some View {
            Label(title(for: source), systemImage: systemImage(for: source))
                .labelStyle(.titleAndIcon)
                .font(UIDevice.isTV ? .caption : .caption2)
                .fontWeight(.semibold)
                .lineLimit(1)
                .padding(.horizontal, UIDevice.isTV ? 14 : 8)
                .padding(.vertical, UIDevice.isTV ? 6 : 3)
                .foregroundStyle(accentColor.overlayColor)
                .background(accentColor.opacity(0.85), in: .capsule)
        }

        private func title(for source: CouchDeciderCandidate.Source) -> String {
            switch source {
            case .picked:
                isGroup ? L10n.CouchDecider.pickedForThisCouch : L10n.CouchDecider.pickedForYou
            case .nextUp:
                isGroup ? L10n.CouchDecider.nextUpTogether : L10n.CouchDecider.nextUpSolo
            case .newForEveryone:
                isGroup ? L10n.CouchDecider.newForAllOfYou : L10n.CouchDecider.newForYou
            case .library:
                L10n.CouchDecider.fromYourLibrary
            }
        }

        private func systemImage(for source: CouchDeciderCandidate.Source) -> String {
            switch source {
            case .picked:
                "heart.fill"
            case .nextUp:
                "forward.end.fill"
            case .newForEveryone:
                "sparkles"
            case .library:
                "books.vertical"
            }
        }
    }
}
