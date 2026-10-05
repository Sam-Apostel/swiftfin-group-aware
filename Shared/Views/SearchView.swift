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

struct SearchView: View {

    @Default(.Customization.Search.enabledDrawerFilters)
    private var enabledDrawerFilters

    @FocusState
    private var isSearchFocused: Bool

    #if os(tvOS)
    @FocusState
    private var focusedFilter: FilterTrack.FocusTarget?

    @InjectedObject(\.seerrService)
    private var seerrService: SeerrService

    @Router
    private var router
    #endif

    @State
    private var searchQuery = ""

    @StateObject
    private var focusCoordinator: FocusCoordinator = .init()
    @StateObject
    private var viewModel = SearchViewModel()

    @TabItemSelected
    private var tabItemSelected

    @ViewBuilder
    private var suggestionsView: some View {
        VStack(spacing: 20) {
            ForEach(viewModel.suggestions) { item in
                Button(item.displayTitle) {
                    searchQuery = item.displayTitle
                }
                #if os(tvOS)
                .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                #endif
            }
        }
    }

    #if os(tvOS)

    // MARK: - Find on Seerr

    /// The query for "Find “Paddington” on Seerr" (#49), or `nil` when the button is hidden:
    /// without Seerr, with a child on the couch (fails closed without a couch), or without a query.
    private var seerrHandOffQuery: String? {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        guard query.isNotEmpty,
              seerrService.isConfigured,
              let couch = Container.shared.currentUserSession()?.couch,
              !couch.hasChild
        else { return nil }

        return query
    }

    @ViewBuilder
    private var findOnSeerrButton: some View {
        if let query = seerrHandOffQuery {
            Button {
                router.route(to: .seerrSearch(query: query))
            } label: {
                Label(L10n.SeerrDiscover.findOnSeerr(query), systemImage: "popcorn.fill")
                    .lineLimit(1)
                    .padding(.horizontal, 40)
                    .frame(minWidth: 400)
            }
            .fontWeight(.semibold)
            .backport
            .buttonStyle(.glass)
            .frame(height: 75)
            .focusSection()
            .padding(.vertical, EdgeInsets.edgePadding)
        }
    }
    #endif

    @ViewBuilder
    private var resultsView: some View {
        VStack(spacing: 0) {
            if viewModel.isEmpty {
                Text(L10n.noResults)
            } else {
                ContentGroupVStack(
                    groups: viewModel.itemContentGroupViewModel.groups
                )
            }

            #if os(tvOS)
            findOnSeerrButton
            #endif
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                #if os(tvOS)
                if enabledDrawerFilters.isNotEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 20) {
                            FilterTrack(viewModel: viewModel.filterViewModel, types: enabledDrawerFilters, focus: $focusedFilter)
                        }
                    }
                    .scrollClipDisabled()
                    .scrollIndicators(.hidden)
                    .frame(height: 64)
                    .coordinatedFocusScope(
                        $focusedFilter,
                        values: enabledDrawerFilters.map(FilterTrack.FocusTarget.filter) +
                            (viewModel.filterViewModel.hasActiveFilters ? [.reset] : [])
                    )
                    .edgePadding(.horizontal)
                    .padding(.vertical, EdgeInsets.itemSpacing)
                }
                #endif

                ZStack {
                    switch viewModel.state {
                    case .error:
                        viewModel.error.map(ErrorView.init)

                    case .initial:
                        if viewModel.canSearch {
                            resultsView
                        } else {
                            suggestionsView
                        }

                    case .searching:
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity)
                .focusSection()
            }
        }
        .ignoresSafeArea(edges: .horizontal)
        .scrollIndicators(.hidden)
        .animation(.linear(duration: 0.2), value: viewModel.state)
        .ignoresSafeArea(.keyboard)
        .navigationTitle(L10n.search)
        .toolbarTitleDisplayMode(.inline)
        .searchFocused($isSearchFocused)
        .onReceive(tabItemSelected) { event in
            if event.isRepeat, event.isRoot {
                isSearchFocused = true
            }
        }
        .onFirstAppear {
            viewModel.getSuggestions()
        }
        .onChange(of: searchQuery) {
            viewModel.search(query: searchQuery)
        }
        .searchable(
            text: $searchQuery,
            prompt: L10n.search
        )
        .environmentObject(focusCoordinator)
        #if os(tvOS)
        .modifier(SearchSafeAreaModifier())
        .onReceive(viewModel.filterViewModel.$currentFilters) { filters in
            searchQuery = filters.query ?? ""
        }
        #endif
        #if os(iOS)
        .navigationBarFilterDrawer(
            viewModel: viewModel.filterViewModel,
            types: enabledDrawerFilters
        )
        #endif
    }
}
