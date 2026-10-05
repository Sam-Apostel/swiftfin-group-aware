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

                WhyTags(sources: candidate.sources)
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

    /// Why this card is in the deck: "Picked for you", "Next up together", "New for all of you".
    struct WhyTags: View {

        @Default(.accentColor)
        private var accentColor

        let sources: Set<CouchDeciderCandidate.Source>

        private var orderedSources: [CouchDeciderCandidate.Source] {
            CouchDeciderCandidate.Source.allCases.filter { sources.contains($0) }
        }

        var body: some View {
            if orderedSources.isNotEmpty {
                HStack(spacing: UIDevice.isTV ? 16 : 6) {
                    ForEach(orderedSources, id: \.self) { source in
                        tag(for: source)
                    }
                }
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
                L10n.CouchDecider.pickedForYou
            case .nextUp:
                L10n.CouchDecider.nextUpTogether
            case .newForEveryone:
                L10n.CouchDecider.newForAllOfYou
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
            }
        }
    }
}
