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

/// A universe as a themed timeline: everything in it, in release, story or historical order,
/// or one lane per creator. What's in the library plays; the rest shows where to get it.
struct UniverseView: View {

    @Default(.universesThemed)
    private var isThemed

    @Router
    private var router

    @StateObject
    private var viewModel: UniverseViewModel

    @State
    private var timeline: UniverseTimeline?
    @State
    private var onlyLibrary = false
    @State
    private var artworkColor: Color?

    init(universeID: String) {
        self._viewModel = StateObject(wrappedValue: UniverseViewModel(universeID: universeID))
    }

    private func style(for universe: Universe) -> UniverseStyle {
        UniverseStyle(theme: universe.theme, isThemed: isThemed)
    }

    private func accent(for universe: Universe) -> Color {
        artworkColor ?? style(for: universe).presetColor
    }

    private func currentTimeline(for universe: Universe) -> UniverseTimeline {
        timeline ?? UniverseLayout.defaultTimeline(for: universe)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            if let universe = viewModel.universe {
                content(universe)
            } else if let error = viewModel.error {
                ErrorView(error: error)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(viewModel.universe?.name ?? L10n.Universes.title)
        .toolbarTitleDisplayMode(.inline)
        .refreshable {
            await viewModel.load(force: true)
        }
        .task {
            await viewModel.load()
        }
        .errorMessage(alertError)
    }

    /// Errors after the universe loaded (a failed answer); before that, the error replaces the screen.
    private var alertError: Binding<Error?> {
        Binding(
            get: { viewModel.universe == nil ? nil : viewModel.error },
            set: { viewModel.error = $0 }
        )
    }

    @ViewBuilder
    private func content(_ universe: Universe) -> some View {
        let style = self.style(for: universe)
        let accent = self.accent(for: universe)
        let timeline = currentTimeline(for: universe)
        let sections = UniverseLayout.sections(for: universe, timeline: timeline, onlyLibrary: onlyLibrary)

        ScrollView {
            LazyVStack(alignment: .leading, spacing: UIDevice.isTV ? 40 : 24) {
                header(universe, style: style, accent: accent)

                controls(universe, timeline: timeline)

                if let next = viewModel.nextUp(on: timeline) {
                    nextUpCard(next.entry, item: next.item, style: style, accent: accent)
                }

                ForEach(sections) { section in
                    sectionView(section, universe: universe, timeline: timeline, style: style, accent: accent)
                }

                related(universe, style: style)
            }
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background {
            if style.isThemed {
                UniverseBackground(style: style, color: accent, seed: universe.id)
            }
        }
        .environment(\.colorScheme, style.isThemed ? .dark : colorSchemeFallback)
        .animation(.easeInOut(duration: 0.25), value: timeline)
        .animation(.easeInOut(duration: 0.25), value: onlyLibrary)
    }

    @Environment(\.colorScheme)
    private var colorSchemeFallback

    // MARK: - Header

    private func header(_ universe: Universe, style: UniverseStyle, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: UIDevice.isTV ? 16 : 10) {
            if let hero = viewModel.heroItem {
                ImageView(hero.imageSource(
                    .backdrop,
                    itemID: hero.id,
                    environment: ImageSourceOptions(maxWidth: UIDevice.isTV ? 1920 : 1200)
                ))
                    .image { (image: UIImage) in
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .onAppear {
                                resolveColor(from: image)
                            }
                    }
                    .aspectRatio(16 / 9, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: UIDevice.isTV ? 420 : 220)
                    .clipped()
                    .mask {
                        LinearGradient(colors: [.black, .black, .clear], startPoint: .top, endPoint: .bottom)
                    }
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: UIDevice.isTV ? 14 : 8) {
                Label(universe.kind.displayTitle, systemImage: universe.kind.systemImage)
                    .font(style.label())
                    .foregroundStyle(accent)
                    .textCase(.uppercase)

                Text(universe.name)
                    .font(style.font(.largeTitle, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)

                if let description = universe.description, description.isNotEmpty {
                    Text(description.prefix(1).uppercased() + description.dropFirst())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 14) {
                    Text(L10n.Universes.inLibrary(universe.counts.inLibrary, of: universe.counts.entries))

                    if viewModel.libraryEntries.isNotEmpty {
                        Text(L10n.Universes.watched(viewModel.watchedCount, of: viewModel.libraryEntries.count))
                    }
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

                if viewModel.libraryEntries.isNotEmpty {
                    ProgressView(value: Double(viewModel.watchedCount), total: Double(max(viewModel.libraryEntries.count, 1)))
                        .tint(accent)
                        .frame(maxWidth: 320)
                }
            }
            .edgePadding(.horizontal)
            .padding(.top, viewModel.heroItem == nil ? 20 : -40)
        }
    }

    private func resolveColor(from image: UIImage) {
        guard isThemed, artworkColor == nil else { return }

        let binding = $artworkColor
        Task.detached(priority: .utility) {
            guard let color = image.interestingColor() else { return }

            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.6)) {
                    binding.wrappedValue = color
                }
            }
        }
    }

    // MARK: - Controls

    @ViewBuilder
    private func controls(_ universe: Universe, timeline: UniverseTimeline) -> some View {
        let available = universe.availableTimelines

        VStack(alignment: .leading, spacing: 12) {
            if available.count > 1 {
                Picker(L10n.Universes.title, selection: timelineSelection(current: timeline)) {
                    ForEach(available) { option in
                        Text(UniverseLayout.title(for: option, in: universe))
                            .tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }

            if universe.counts.inLibrary < universe.counts.entries {
                Picker(L10n.Universes.showEverything, selection: $onlyLibrary) {
                    Text(L10n.Universes.showEverything)
                        .tag(false)
                    Text(L10n.Universes.showOnlyLibrary)
                        .tag(true)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: UIDevice.isTV ? 700 : 320)
            }
        }
        .edgePadding(.horizontal)
        .focusSection()
    }

    private func timelineSelection(current: UniverseTimeline) -> Binding<UniverseTimeline> {
        Binding(
            get: { current },
            set: { timeline = $0 }
        )
    }

    // MARK: - Next up

    private func nextUpCard(_ entry: UniverseEntry, item: BaseItemDto, style: UniverseStyle, accent: Color) -> some View {
        Button {
            router.route(to: .item(item: item))
        } label: {
            HStack(spacing: UIDevice.isTV ? 24 : 12) {
                Image(systemName: "play.fill")
                    .font(.title3)
                    .foregroundStyle(.black)
                    .frame(width: UIDevice.isTV ? 70 : 44, height: UIDevice.isTV ? 70 : 44)
                    .background(accent, in: .circle)

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.nextUp)
                        .font(style.label())
                        .foregroundStyle(accent)
                        .textCase(.uppercase)

                    Text(entry.title)
                        .font(style.font(.headline, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.forward")
                    .foregroundStyle(.secondary)
            }
            .padding(UIDevice.isTV ? 24 : 12)
            #if os(iOS)
            .background(.white.opacity(0.08), in: .rect(cornerRadius: 16))
            #endif
        }
        #if os(tvOS)
        .buttonStyle(.card)
        #else
        .buttonStyle(.plain)
        #endif
        .edgePadding(.horizontal)
    }

    // MARK: - Sections

    @ViewBuilder
    private func sectionView(
        _ section: UniverseSection,
        universe: Universe,
        timeline: UniverseTimeline,
        style: UniverseStyle,
        accent: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: UIDevice.isTV ? 20 : 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(section.title)
                    .font(style.font(.title2, weight: .bold))
                    .accessibilityAddTraits(.isHeader)

                if let subtitle = section.subtitle {
                    Text(subtitle)
                        .font(style.label())
                        .foregroundStyle(.secondary)
                }
            }
            .edgePadding(.horizontal)

            if timeline == .lanes {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: UIDevice.isTV ? 40 : 14) {
                        ForEach(section.entries) { entry in
                            entryButton(entry, universe: universe) {
                                UniverseEntryTile(
                                    entry: entry,
                                    item: entry.jellyfinItemId.flatMap { viewModel.items[$0] },
                                    style: style,
                                    accent: accent,
                                    caption: entry.year.map(String.init)
                                )
                            }
                        }
                    }
                    .edgePadding(.horizontal)
                }
                .scrollClipDisabled()
                .scrollIndicators(.hidden)
            } else {
                // The rail: a line down the side of the timeline, like a ruler through the years.
                VStack(alignment: .leading, spacing: UIDevice.isTV ? 16 : 6) {
                    ForEach(Array(section.entries.enumerated()), id: \.element.id) { index, entry in
                        entryButton(entry, universe: universe) {
                            UniverseEntryCard(
                                entry: entry,
                                item: entry.jellyfinItemId.flatMap { viewModel.items[$0] },
                                style: style,
                                accent: accent,
                                caption: caption(for: entry, timeline: timeline),
                                number: timeline == .chronological ? index + 1 : nil
                            )
                        }
                    }
                }
                .padding(.leading, UIDevice.isTV ? 24 : 10)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(LinearGradient(colors: [accent, accent.opacity(0.1)], startPoint: .top, endPoint: .bottom))
                        .frame(width: UIDevice.isTV ? 4 : 2)
                }
                .edgePadding(.horizontal)
            }
        }
        .focusSection()
    }

    private func caption(for entry: UniverseEntry, timeline: UniverseTimeline) -> String? {
        switch timeline {
        case .historical:
            guard let historical = entry.positions.historical else { return nil }

            let span = L10n.Universes.span(from: historical.start, to: historical.end)
            return historical.label.map { "\(span) · \($0)" } ?? span

        default:
            return entry.year.map(String.init)
        }
    }

    // MARK: - Actions

    private func entryButton<Content: View>(
        _ entry: UniverseEntry,
        universe: Universe,
        @ViewBuilder label: () -> Content
    ) -> some View {
        Button {
            open(entry)
        } label: {
            label()
        }
        #if os(tvOS)
        .buttonStyle(.card)
        #else
        .buttonStyle(.plain)
        #endif
        .contextMenu {
            if entry.status == .suggested {
                Button(L10n.Universes.belongsHere, systemImage: "checkmark") {
                    Task { await viewModel.answer(entry: entry, accept: true) }
                }
            }

            Button(L10n.Universes.notPartOfUniverse, systemImage: "xmark", role: .destructive) {
                Task { await viewModel.answer(entry: entry, accept: false) }
            }

            #if os(iOS)
            if let url = entry.infoURL {
                Button(L10n.Universes.moreInfo, systemImage: "info.circle") {
                    UIApplication.shared.open(url)
                }
            }
            #endif
        }
    }

    private func open(_ entry: UniverseEntry) {
        if let id = entry.jellyfinItemId, let item = viewModel.items[id] {
            router.route(to: .item(item: item))
        } else if let id = entry.jellyfinItemId {
            router.route(to: .item(id: id))
        } else if let seerr = entry.seerr, Container.shared.seerrService().isConfigured {
            router.route(to: .seerrMedia(mediaType: seerr.mediaType, tmdbID: seerr.tmdbId))
        } else {
            #if os(iOS)
            if let url = entry.youtubeURL ?? entry.infoURL {
                UIApplication.shared.open(url)
            }
            #endif
        }
    }

    // MARK: - Related

    @ViewBuilder
    private func related(_ universe: Universe, style: UniverseStyle) -> some View {
        let ids = universe.parentIds + universe.childIds

        if ids.isNotEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.Universes.title)
                    .font(style.font(.title3, weight: .bold))
                    .edgePadding(.horizontal)

                ScrollView(.horizontal) {
                    HStack(spacing: EdgeInsets.itemSpacing) {
                        ForEach(ids, id: \.self) { id in
                            Button {
                                router.route(to: .universe(id: id))
                            } label: {
                                Label(
                                    relatedName(id),
                                    systemImage: universe.parentIds.contains(id) ? "arrow.up.forward" : "arrow.down.forward"
                                )
                            }
                            .foregroundStyle(.primary, .secondary)
                        }
                    }
                    .labelStyle(.leadingIcon)
                    .buttonStyle(.capsule)
                    .edgePadding(.horizontal)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            }
            .focusSection()
        }
    }

    private func relatedName(_ id: String) -> String {
        Container.shared.universeService().summaries.first { $0.id == id }?.name
            ?? id.replacing("curated-", with: "").replacing("-", with: " ").capitalized
    }
}
