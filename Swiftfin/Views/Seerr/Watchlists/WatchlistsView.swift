//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

/// "Our watchlists": the household's audience-tagged watchlist, grouped by who it is for.
struct WatchlistsView: View {

    @Router
    private var router

    @StateObject
    private var viewModel = WatchlistsViewModel()

    // MARK: - Body

    var body: some View {
        ZStack {
            if viewModel.entries.isEmpty {
                if viewModel.isRefreshing || !viewModel.hasLoaded {
                    ProgressView()
                } else {
                    emptyView
                }
            } else if viewModel.sections.isEmpty {
                noMatchesView
            } else {
                listView
            }
        }
        .animation(.linear(duration: 0.2), value: viewModel.entries.isEmpty)
        .navigationTitle(L10n.Watchlists.title)
        .toolbarTitleDisplayMode(.inline)
        .refreshable {
            await viewModel.refresh()
        }
        .onFirstAppear {
            viewModel.onFirstAppear()
        }
        .topBarTrailing {
            if viewModel.isRefreshing, viewModel.entries.isNotEmpty {
                ProgressView()
            }

            filterMenu
        }
        .errorMessage($viewModel.error)
    }

    // MARK: - States

    @ViewBuilder
    private var emptyView: some View {
        ScrollView {
            ContentUnavailableView(
                L10n.Watchlists.emptyTitle,
                systemImage: "bookmark",
                description: Text(L10n.Watchlists.emptyDescription)
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 80)
        }
    }

    @ViewBuilder
    private var noMatchesView: some View {
        ScrollView {
            ContentUnavailableView(
                L10n.Watchlists.noMatchesTitle,
                systemImage: "line.3.horizontal.decrease.circle",
                description: Text(L10n.Watchlists.noMatchesDescription)
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 80)
        }
    }

    // MARK: - List

    @ViewBuilder
    private var listView: some View {
        List {
            ForEach(viewModel.sections) { section in
                Section {
                    ForEach(section.entries) { entry in
                        row(for: entry)
                    }
                } header: {
                    sectionHeader(for: section)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func sectionHeader(for section: WatchlistsSection) -> some View {
        HStack(alignment: .center) {
            Image(systemName: viewModel.systemImage(for: section.audience))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            AudienceLabel(audience: section.audience, users: viewModel.users)

            Spacer(minLength: 8)

            Text(L10n.Watchlists.itemCount(section.entries.count))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .textCase(nil)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func row(for entry: AudienceWatchlistEntry) -> some View {
        EntryRow(
            entry: entry,
            libraryItem: viewModel.libraryItem(for: entry),
            availability: viewModel.availability(for: entry)
        ) {
            select(entry)
        } onChangeAudience: {
            changeAudience(of: entry)
        } onRemove: {
            Task {
                await viewModel.remove(entry)
            }
        }
    }

    // MARK: - Filter

    @ViewBuilder
    private var filterMenu: some View {
        let systemImage = if #available(iOS 26, *) {
            "line.3.horizontal.decrease"
        } else {
            "line.3.horizontal.decrease.circle"
        }

        Menu(
            L10n.filters,
            systemImage: systemImage
        ) {
            Picker(selection: $viewModel.filter) {
                ForEach(WatchlistsFilter.allCases) { filter in
                    Label(
                        filter.displayTitle,
                        systemImage: filter.systemImage
                    )
                    .tag(filter)
                }
            } label: {
                Text(L10n.Watchlists.filter)
                Text(viewModel.filter.displayTitle)
                Image(systemName: viewModel.filter.systemImage)
            }
            .pickerStyle(.inline)
        }
    }

    // MARK: - Audience picker

    private func changeAudience(of entry: AudienceWatchlistEntry) {
        let viewModel = self.viewModel

        router.route(
            to: .audiencePicker(
                title: entry.title,
                initialAudience: entry.audience,
                isExisting: true,
                onSave: { audience in
                    Task {
                        await viewModel.changeAudience(of: entry, to: audience)
                    }
                },
                onRemove: {
                    Task {
                        await viewModel.remove(entry)
                    }
                }
            )
        )
    }

    // MARK: - Routing

    private func select(_ entry: AudienceWatchlistEntry) {
        // In the library: open the normal Swiftfin item view
        if let item = viewModel.libraryItem(for: entry) {
            router.route(to: .item(item: item))
            return
        }

        if viewModel.availability(for: entry) == .inLibrary, let itemID = viewModel.jellyfinItemID(for: entry) {
            router.route(to: .item(id: itemID))
            return
        }

        // Not (yet) in the library: Seerr detail for TMDB entries
        if let tmdbID = entry.tmdbID {
            let mediaType: SeerrMediaType = entry.kind == .movie ? .movie : .tv
            router.route(to: .seerrMedia(mediaType: mediaType, tmdbID: tmdbID))
            return
        }

        // Jellyfin-only entry that could not be resolved: let the item view show its own state
        if let itemID = entry.jellyfinItemID {
            router.route(to: .item(id: itemID))
        }
    }
}
