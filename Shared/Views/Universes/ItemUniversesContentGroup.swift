//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import FactoryKit
import JellyfinAPI
import SwiftUI

/// "Part of": the universes an item belongs to, on its page. Hidden when there are none
/// or the Universes app isn't connected.
struct ItemUniversesContentGroup: ContentGroup {

    @MainActor
    final class ViewModel: ObservableObject, WithRefresh {

        @Published
        private(set) var universes: [UniverseSummary] = []

        private let itemID: String?
        private let alsoIDs: [String]

        init(item: BaseItemDto) {
            // Episodes and seasons belong to whatever their show belongs to.
            self.itemID = item.id
            self.alsoIDs = [item.seriesID, item.parentID].compactMap(\.self).filter { $0 != item.id }
        }

        func refresh() {
            Task {
                await refresh()
            }
        }

        func refresh() async {
            guard let itemID else { return }

            universes = await Container.shared.universeService().universes(forItemID: itemID, alsoIDs: alsoIDs)
        }
    }

    let id = "universes"
    let viewModel: ViewModel

    var _shouldBeResolved: Bool {
        viewModel.universes.isNotEmpty
    }

    init(item: BaseItemDto) {
        self.viewModel = ViewModel(item: item)
    }

    func body(with viewModel: ViewModel) -> Body {
        Body(viewModel: viewModel)
    }

    struct Body: View {

        @Default(.universesThemed)
        private var isThemed

        @Router
        private var router

        @ObservedObject
        var viewModel: ViewModel

        var body: some View {
            ContentGroupSection {
                ScrollView(.horizontal) {
                    HStack(spacing: UIDevice.isTV ? 40 : 14) {
                        ForEach(viewModel.universes) { universe in
                            Button {
                                router.route(to: .universe(id: universe.id))
                            } label: {
                                UniverseSummaryCard(universe: universe, isThemed: isThemed, showsPosition: true)
                            }
                            #if os(tvOS)
                            .buttonStyle(.card)
                            #else
                                .buttonStyle(.plain)
                            #endif
                        }
                    }
                    .edgePadding(.horizontal)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            } header: {
                Text(L10n.Universes.partOf)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .accessibility(addTraits: [.isHeader])
                    .edgePadding(.horizontal)
            }
            .focusSection()
        }
    }
}

/// A universe as a card: its texture and colour, name, kind and how much of it you have.
struct UniverseSummaryCard: View {

    let universe: UniverseSummary
    let isThemed: Bool
    var showsPosition: Bool = false

    private var style: UniverseStyle {
        UniverseStyle(theme: universe.theme, isThemed: isThemed)
    }

    private var width: CGFloat {
        UIDevice.isTV ? 520 : 280
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if style.isThemed {
                UniverseBackground(style: style, color: style.presetColor, seed: universe.id)
            } else {
                Color(white: 0.14)
            }

            UniverseCollage(universe: universe)
                .opacity(0.55)
                .mask {
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                }

            VStack(alignment: .leading, spacing: 4) {
                Label(universe.kind.displayTitle, systemImage: universe.kind.systemImage)
                    .font(style.label(.caption2))
                    .foregroundStyle(style.presetColor)
                    .textCase(.uppercase)

                Text(universe.name)
                    .font(style.font(UIDevice.isTV ? .title2 : .headline, weight: .bold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 8) {
                    if showsPosition, let position = universe.position {
                        Text(L10n.Universes.position(position, of: universe.counts.entries))
                    } else {
                        Text(L10n.Universes.inLibrary(universe.counts.inLibrary, of: universe.counts.entries))
                    }

                    if let span = universe.span {
                        Text(L10n.Universes.span(from: span.from, to: span.to))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(UIDevice.isTV ? 24 : 14)
        }
        .frame(width: width, height: width * 0.56)
        .clipShape(.rect(cornerRadius: UIDevice.isTV ? 20 : 14))
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .combine)
    }
}

/// A few posters from the universe, fanned out.
struct UniverseCollage: View {

    let universe: UniverseSummary

    private var sources: [[ImageSource]] {
        let library: [[ImageSource]] = universe.sampleItemIds.prefix(5).compactMap { id in
            Self.posterSource(itemID: id).map { [$0] }
        }
        let ghosts = universe.sampleImageUrls.prefix(max(0, 5 - library.count)).map { [ImageSource(url: $0)] }
        return library + ghosts
    }

    /// A poster URL without a tag; Jellyfin serves the current primary image.
    static func posterSource(itemID: String) -> ImageSource? {
        guard let client = Container.shared.currentUserSession()?.client else { return nil }

        let parameters = Paths.GetItemImageParameters(maxWidth: 300, quality: 80)
        let request = Paths.getItemImage(itemID: itemID, imageType: ImageType.primary.rawValue, parameters: parameters)
        return client.url(with: request).map { ImageSource(url: $0) }
    }

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height * 0.9
            HStack(spacing: -height * 0.18) {
                ForEach(Array(sources.enumerated()), id: \.offset) { index, source in
                    ImageView(source)
                        .placeholder { _ in
                            Color.clear
                        }
                        .failure {
                            Color.clear
                        }
                        .aspectRatio(2 / 3, contentMode: .fill)
                        .frame(height: height)
                        .clipShape(.rect(cornerRadius: 6))
                        .rotationEffect(.degrees(Double(index - 2) * 4))
                        .shadow(radius: 6)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.trailing, 12)
            .padding(.top, 8)
        }
        .accessibilityHidden(true)
    }
}
