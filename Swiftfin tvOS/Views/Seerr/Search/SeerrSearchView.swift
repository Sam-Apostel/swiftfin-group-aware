//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

/// Searches TMDB through Seerr with the standard tvOS search keyboard (and dictation).
///
/// A pushed screen, so the Discover hero keeps the initial focus. Reuses `DiscoverViewModel`
/// for its debounced, paged and cancellable search (family picks only in kid mode, #49);
/// its rows (`refresh`) are never loaded here.
struct SeerrSearchView: View {

    @Router
    private var router

    @State
    private var searchQuery = ""

    @StateObject
    private var viewModel = DiscoverViewModel()

    /// - Parameter query: Seeds the search field, e.g. from the library Search tab (#49).
    init(query: String? = nil) {
        _searchQuery = State(initialValue: query ?? "")
    }

    private let columns: [GridItem] = Array(
        repeating: GridItem(.flexible(), spacing: EdgeInsets.itemSpacing, alignment: .top),
        count: 6
    )

    private var isQueryEmpty: Bool {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isSearching: Bool {
        viewModel.background.is(.searching)
    }

    // MARK: - Kid Mode

    /// Kid mode (#49): "Showing family picks because Tuur is on the couch".
    private var familyFilterMessage: String {
        L10n.SeerrDiscover.familyPicksFooter(childNames: viewModel.childMemberNames)
    }

    private var familyFilterFooter: some View {
        Label(familyFilterMessage, systemImage: "figure.and.child.holdinghands")
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .edgePadding(.horizontal)
            .padding(.bottom, EdgeInsets.edgePadding)
    }

    private var familyFilterNoResultsView: some View {
        ContentUnavailableView {
            Label(L10n.noResults, systemImage: "magnifyingglass")
        } description: {
            Text(familyFilterMessage)
        }
    }

    // MARK: - Results

    private var resultsGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 60) {
                ForEach(viewModel.searchResults) { media in
                    PosterButton(
                        item: media,
                        displayType: .portrait
                    ) { namespace in
                        media.libraryDidSelectElement(router: router, in: namespace)
                    }
                    .onAppear {
                        if media.id == viewModel.searchResults.last?.id {
                            viewModel.getNextSearchPage()
                        }
                    }
                }
            }
            .edgePadding()
            .focusSection()

            if viewModel.isFamilyFiltered {
                familyFilterFooter
            }
        }
        .scrollClipDisabled()
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var content: some View {
        if isQueryEmpty {
            ContentUnavailableView(
                L10n.SeerrTV.searchHint,
                systemImage: "magnifyingglass"
            )
        } else if viewModel.searchResults.isNotEmpty {
            resultsGrid
        } else if isSearching || !viewModel.hasSearched {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.searchError {
            ContentUnavailableView(
                L10n.SeerrDiscover.searchFailed,
                systemImage: "exclamationmark.magnifyingglass",
                description: Text(error.localizedDescription)
            )
        } else if viewModel.isFamilyFiltered {
            familyFilterNoResultsView
        } else {
            ContentUnavailableView.search(text: searchQuery)
        }
    }

    // MARK: - Body

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.linear(duration: 0.2), value: isSearching)
            .ignoresSafeArea(edges: .horizontal)
            .searchable(
                text: $searchQuery,
                prompt: L10n.SeerrDiscover.searchPrompt
            )
            .onChange(of: searchQuery) {
                viewModel.searchQuery = searchQuery
            }
            .onFirstAppear {
                // A query handed over from the library Search tab searches right away
                if !isQueryEmpty {
                    viewModel.searchQuery = searchQuery
                }
            }
            // Same chrome as the Search tab: no navigation bar, the native search field on top
            .toolbar(.hidden, for: .navigationBar)
            .modifier(SearchSafeAreaModifier())
    }
}
