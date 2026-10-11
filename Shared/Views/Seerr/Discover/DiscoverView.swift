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

struct DiscoverView: View {

    @Default(.accentColor)
    private var accentColor

    @InjectedObject(\.seerrService)
    private var seerrService

    #if os(tvOS)
    @Environment(\.tabSafeAreaInsets)
    private var tabSafeAreaInsets
    #endif

    @Router
    private var router

    @State
    private var searchQuery = ""

    @StateObject
    private var viewModel = DiscoverViewModel()

    @TabItemSelected
    private var tabItemSelected

    /// Changes whenever Seerr is connected, disconnected or reconfigured.
    private var clientIdentity: ObjectIdentifier? {
        seerrService.client.map { ObjectIdentifier($0) }
    }

    // MARK: - Not Configured

    private var notConfiguredView: some View {
        FinEmptyView(
            L10n.SeerrDiscover.notConfiguredTitle,
            description: L10n.SeerrDiscover.notConfiguredDescription
        ) {
            Button {
                router.route(to: .seerrSettings)
            } label: {
                Text(L10n.connect)
                    .frame(maxWidth: .infinity)
            }
            .fontWeight(.semibold)
            .backport
            .buttonStyle(.glassProminent.shadow(false))
            .tint(Color.Couchfin.fin)
            .controlSize(.large)
            .frame(maxWidth: UIDevice.isTV ? 500 : 300)
        }
    }

    // MARK: - Rows

    private var rowsView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: UIDevice.isTV ? 50 : 20) {
                    Color.clear
                        .frame(height: 0)
                        .id("top")

                    #if os(tvOS)
                    // No search field on tvOS: the keyboard would push the rows off screen,
                    // so search gets its own screen.
                    HStack(spacing: 40) {
                        WatchlistsCard()

                        SearchButton()
                    }
                    .edgePadding(.horizontal)
                    .focusSection()
                    #else
                    WatchlistsCard()
                        .edgePadding(.horizontal)
                    #endif

                    ForEach(viewModel.rows) { row in
                        RowSection(row: row)
                    }
                }
                .padding(.vertical, EdgeInsets.edgePadding)
                #if os(tvOS)
                .padding(.top, tabSafeAreaInsets.top)
                #endif
            }
            .scrollIndicators(.hidden)
            #if os(tvOS)
            .ignoresSafeArea(.container, edges: [.horizontal, .top])
            #else
            .ignoresSafeArea(edges: .horizontal)
            #endif
            .refreshable {
                await viewModel.background.refresh()
            }
            .onReceive(tabItemSelected) { event in
                if event.isRepeat, event.isRoot {
                    withAnimation {
                        proxy.scrollTo("top", anchor: .top)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var discoverContent: some View {
        switch viewModel.state {
        case .initial, .refreshing:
            #if os(tvOS)
            SwimmingFin()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(edges: .all)
            #else
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            #endif

        case .error:
            viewModel.error.map(ErrorView.init)

        case .content:
            rowsView
        }
    }

    // MARK: - Configured

    #if os(tvOS)
    @ViewBuilder
    private var configuredContent: some View {
        discoverContent
            .animation(.linear(duration: 0.2), value: viewModel.state)
            .refreshable {
                await viewModel.refresh()
            }
    }
    #else
    @ViewBuilder
    private var configuredContent: some View {
        ZStack {
            if viewModel.isSearchActive {
                SearchResultsView(viewModel: viewModel)
            } else {
                discoverContent
            }
        }
        .animation(.linear(duration: 0.2), value: viewModel.state)
        .animation(.linear(duration: 0.2), value: viewModel.isSearchActive)
        .searchable(
            text: $searchQuery,
            prompt: L10n.SeerrDiscover.searchPrompt
        )
        .onChange(of: searchQuery) {
            viewModel.searchQuery = searchQuery
        }
        .refreshable {
            await viewModel.refresh()
        }
    }
    #endif

    var body: some View {
        ZStack {
            if seerrService.isConfigured {
                configuredContent
            } else {
                notConfiguredView
            }
        }
        .navigationTitle(L10n.SeerrDiscover.title)
        #if os(tvOS)
        .toolbar(router.isRootOfPath ? .hidden : .automatic, for: .navigationBar)
        #else
        .toolbarTitleDisplayMode(router.isRootOfPath ? .inlineLarge : .inline)
        #endif
        .onFirstAppear {
            if seerrService.isConfigured {
                viewModel.refresh()
            }
        }
        .onChange(of: clientIdentity) {
            if seerrService.isConfigured {
                viewModel.refresh()
            }
        }
    }
}
