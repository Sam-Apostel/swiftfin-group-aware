//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension DiscoverView {

    /// Poster grid of Seerr search results, paging in more results near the end.
    struct SearchResultsView: View {

        @Router
        private var router

        @ObservedObject
        var viewModel: DiscoverViewModel

        private var columns: [GridItem] {
            if UIDevice.isPhone {
                Array(
                    repeating: GridItem(.flexible(), spacing: EdgeInsets.itemSpacing, alignment: .top),
                    count: 3
                )
            } else {
                [GridItem(.adaptive(minimum: 140), spacing: EdgeInsets.itemSpacing, alignment: .top)]
            }
        }

        private var isSearching: Bool {
            viewModel.background.is(.searching)
        }

        /// Kid mode (#49): "Showing family picks because Tuur is on the couch".
        private var familyFilterMessage: String {
            L10n.SeerrDiscover.familyPicksFooter(childNames: viewModel.childMemberNames)
        }

        private var familyFilterFooter: some View {
            Label(familyFilterMessage, systemImage: "figure.and.child.holdinghands")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .edgePadding(.horizontal)
                .padding(.bottom, EdgeInsets.edgePadding)
        }

        private var gridView: some View {
            ScrollView {
                LazyVGrid(columns: columns, spacing: EdgeInsets.itemSpacing) {
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

                if viewModel.isFamilyFiltered {
                    familyFilterFooter
                }
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.immediately)
        }

        private var familyFilterNoResultsView: some View {
            ContentUnavailableView {
                Label(L10n.noResults, systemImage: "magnifyingglass")
            } description: {
                Text(familyFilterMessage)
            }
        }

        @ViewBuilder
        private var content: some View {
            if viewModel.searchResults.isNotEmpty {
                gridView
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
                ContentUnavailableView.search(text: viewModel.searchQuery)
            }
        }

        var body: some View {
            content
                .animation(.linear(duration: 0.2), value: isSearching)
                .refreshable {
                    await viewModel.search(query: viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines))
                }
        }
    }
}
