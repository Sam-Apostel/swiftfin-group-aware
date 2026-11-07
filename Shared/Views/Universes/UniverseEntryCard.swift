//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

/// One work on a universe's timeline: a poster, its title and where it sits.
/// What you don't have yet is drawn as a "ghost": dimmed, with where to get it.
struct UniverseEntryCard: View {

    let entry: UniverseEntry
    let item: BaseItemDto?
    let style: UniverseStyle
    let accent: Color
    /// "1990", "Phase One", "500 BCE – 476": what the current timeline says about it.
    let caption: String?
    /// Story / playlist position on ordered timelines.
    let number: Int?

    private var posterWidth: CGFloat {
        UIDevice.isTV ? 170 : 96
    }

    private var isGhost: Bool {
        !entry.inLibrary
    }

    private var isPlayed: Bool {
        item?.userData?.isPlayed == true
    }

    // MARK: - Poster

    private var imageSources: [ImageSource] {
        if let item {
            let options = ImageSourceOptions(maxWidth: posterWidth)
            let primary = item.imageSource(.primary, itemID: item.id, environment: options)
            let series = item.imageSource(.primary, itemID: item.seriesID, tag: item.seriesPrimaryImageTag, environment: options)
            return [primary, series].compactMap(\.self)
        }
        return entry.imageUrl.map { [ImageSource(url: $0)] } ?? []
    }

    private var aspectRatio: CGFloat {
        entry.kind == .video ? 16 / 9 : 2 / 3
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [accent.opacity(0.5), accent.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing)

            VStack(spacing: 6) {
                Image(systemName: entry.kind.systemImage)
                    .font(.title2)

                Text(entry.title)
                    .font(style.font(.caption2, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 6)
            }
            .foregroundStyle(.white.opacity(0.85))
        }
    }

    private var poster: some View {
        ImageView(imageSources)
            .placeholder { _ in
                placeholder
            }
            .failure {
                placeholder
            }
            .aspectRatio(aspectRatio, contentMode: .fill)
            .frame(width: entry.kind == .video ? posterWidth * 1.6 : posterWidth)
            .clipShape(.rect(cornerRadius: UIDevice.isTV ? 14 : 8))
            .overlay {
                RoundedRectangle(cornerRadius: UIDevice.isTV ? 14 : 8)
                    .strokeBorder(
                        isGhost ? Color.white.opacity(0.35) : Color.white.opacity(0.08),
                        style: StrokeStyle(lineWidth: 1, dash: isGhost ? [4, 3] : [])
                    )
            }
            .overlay(alignment: .topTrailing) {
                if isPlayed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.body)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, accent)
                        .padding(4)
                }
            }
            .saturation(isGhost ? 0.25 : 1)
            .opacity(isGhost ? 0.7 : 1)
    }

    // MARK: - Text

    private var statusText: String? {
        if entry.status == .suggested {
            return L10n.Universes.suggested
        }
        guard isGhost else { return nil }

        switch entry.seerr?.status {
        case "pending", "processing":
            return L10n.Universes.requested
        case "available", "partially-available":
            return L10n.Universes.available
        default:
            return entry.youtubeURL != nil ? L10n.Universes.onYouTube : L10n.Universes.notInLibrary
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: UIDevice.isTV ? 8 : 4) {
            HStack(spacing: 6) {
                if let number {
                    Text(String(number))
                        .font(style.label())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(accent.opacity(0.35), in: .capsule)
                }

                if let caption {
                    Text(caption)
                        .font(style.label())
                        .foregroundStyle(accent)
                }
            }

            Text(entry.title)
                .font(style.font(UIDevice.isTV ? .title3 : .headline, weight: .semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Label(entry.kind.displayTitle, systemImage: entry.kind.systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let statusText {
                Text(statusText)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.white.opacity(0.12), in: .capsule)
            }

            if entry.status == .suggested, let reason = entry.reason {
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        HStack(alignment: .top, spacing: UIDevice.isTV ? 28 : 14) {
            poster

            details
        }
        .padding(UIDevice.isTV ? 18 : 10)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// A smaller card for horizontal rows (creator lanes, item pages).
struct UniverseEntryTile: View {

    let entry: UniverseEntry
    let item: BaseItemDto?
    let style: UniverseStyle
    let accent: Color
    let caption: String?

    private var width: CGFloat {
        UIDevice.isTV ? 360 : 200
    }

    private var imageSources: [ImageSource] {
        if let item {
            let options = ImageSourceOptions(maxWidth: width)
            return [
                item.imageSource(.primary, itemID: item.id, environment: options),
                item.imageSource(.thumb, itemID: item.id, environment: options),
            ].compactMap(\.self)
        }
        return entry.imageUrl.map { [ImageSource(url: $0)] } ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ImageView(imageSources)
                .placeholder { _ in
                    accent.opacity(0.25)
                }
                .failure {
                    ZStack {
                        accent.opacity(0.25)
                        Image(systemName: entry.kind.systemImage)
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .aspectRatio(16 / 9, contentMode: .fill)
                .frame(width: width)
                .clipShape(.rect(cornerRadius: UIDevice.isTV ? 14 : 8))
                .saturation(entry.inLibrary ? 1 : 0.25)
                .opacity(entry.inLibrary ? 1 : 0.7)
                .overlay(alignment: .topTrailing) {
                    if item?.userData?.isPlayed == true {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, accent)
                            .padding(6)
                    }
                }

            if let caption {
                Text(caption)
                    .font(style.label(.caption2))
                    .foregroundStyle(accent)
            }

            Text(entry.title)
                .font(style.font(.subheadline, weight: .semibold))
                .lineLimit(2)
                .frame(width: width, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}
