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
        #if os(iOS)
        .topBarTrailing {
            if viewModel.isRefreshing, viewModel.entries.isNotEmpty {
                ProgressView()
            }

            filterMenu
        }
        #endif
        .errorMessage($viewModel.error)
    }

    // MARK: - States

    @ViewBuilder
    private var emptyView: some View {
        ScrollView {
            FinEmptyView(
                L10n.Watchlists.emptyTitle,
                description: L10n.Watchlists.emptyDescription
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 80)
        }
    }

    @ViewBuilder
    private var noMatchesView: some View {
        #if os(tvOS)
        // The filter has no toolbar on tvOS: keep it reachable to undo it
        VStack(spacing: 40) {
            filterRow
                .frame(maxWidth: 800)

            FinEmptyView(
                L10n.Watchlists.noMatchesTitle,
                description: L10n.Watchlists.noMatchesDescription
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 80)
        #else
        ScrollView {
            FinEmptyView(
                L10n.Watchlists.noMatchesTitle,
                description: L10n.Watchlists.noMatchesDescription
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 80)
        }
        #endif
    }

    // MARK: - List

    @ViewBuilder
    private var listView: some View {
        List {
            #if os(tvOS)
            Section {
                filterRow
            }
            #endif

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
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
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

    #if os(tvOS)
    @ViewBuilder
    private var filterRow: some View {
        ListRowMenu(L10n.Watchlists.filter, selection: $viewModel.filter)
    }
    #else
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
    #endif

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
