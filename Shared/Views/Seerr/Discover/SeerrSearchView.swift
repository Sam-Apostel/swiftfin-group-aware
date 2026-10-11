//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if os(tvOS)
import SwiftUI

/// Seerr search on tvOS, pushed from Discover. On iOS, Discover searches in place.
struct SeerrSearchView: View {

    @State
    private var searchQuery = ""

    @StateObject
    private var viewModel = DiscoverViewModel()

    var body: some View {
        ZStack {
            if viewModel.isSearchActive {
                DiscoverView.SearchResultsView(viewModel: viewModel)
            } else {
                Color.clear
            }
        }
        .animation(.linear(duration: 0.2), value: viewModel.isSearchActive)
        .navigationTitle(L10n.search)
        .searchable(
            text: $searchQuery,
            prompt: L10n.SeerrDiscover.searchPrompt
        )
        .onChange(of: searchQuery) {
            viewModel.searchQuery = searchQuery
        }
    }
}
#endif
