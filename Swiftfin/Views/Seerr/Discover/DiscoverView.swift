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
        ContentUnavailableView {
            Label(L10n.SeerrDiscover.notConfiguredTitle, systemImage: "popcorn.fill")
        } description: {
            Text(L10n.SeerrDiscover.notConfiguredDescription)
        } actions: {
            Button {
                router.route(to: .seerrSettings)
            } label: {
                Text(L10n.connect)
                    .frame(maxWidth: .infinity)
            }
            .fontWeight(.semibold)
            .backport
            .buttonStyle(.glassProminent.shadow(false))
            .tint(accentColor)
            .controlSize(.large)
            .frame(maxWidth: 300)
        }
    }

    // MARK: - Error

    /// Seerr is down, or rejected us: what happened, Retry, and a way to the Seerr settings.
    private var errorView: some View {
        ContentUnavailableView {
            Label(errorTitle, systemImage: errorSystemImage)
        } description: {
            if let recoverySuggestion = (viewModel.error as? LocalizedError)?.recoverySuggestion {
                Text(recoverySuggestion)
            }
        } actions: {
            Button {
                viewModel.refresh()
            } label: {
                Text(L10n.retry)
                    .frame(maxWidth: .infinity)
            }
            .fontWeight(.semibold)
            .backport
            .buttonStyle(.glassProminent.shadow(false))
            .tint(accentColor)
            .controlSize(.large)
            .frame(maxWidth: 300)

            Button {
                router.route(to: .seerrSettings)
            } label: {
                Text(L10n.Seerr.seerrSettings)
                    .frame(maxWidth: .infinity)
            }
            .fontWeight(.semibold)
            .buttonStyle(.bordered)
            .tint(accentColor)
            .controlSize(.large)
            .frame(maxWidth: 300)
        }
    }

    private var errorTitle: String {
        viewModel.error?.localizedDescription ?? L10n.unknownError
    }

    private var errorSystemImage: String {
        guard let seerrError = viewModel.error as? SeerrError else {
            return "exclamationmark.triangle"
        }

        if seerrError.isUnreachable {
            return "wifi.exclamationmark"
        }

        if seerrError.isAuthenticationFailure {
            return "person.crop.circle.badge.exclamationmark"
        }

        return "exclamationmark.triangle"
    }

    // MARK: - Rows

    private var rowsView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Color.clear
                        .frame(height: 0)
                        .id("top")

                    WatchlistsCard()
                        .edgePadding(.horizontal)

                    ForEach(viewModel.rows) { row in
                        RowSection(row: row)
                    }
                }
                .padding(.vertical, EdgeInsets.edgePadding)
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .horizontal)
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
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .error:
            errorView

        case .content:
            rowsView
        }
    }

    // MARK: - Configured

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

    var body: some View {
        ZStack {
            if seerrService.isConfigured {
                configuredContent
            } else {
                notConfiguredView
            }
        }
        .navigationTitle(L10n.SeerrDiscover.title)
        .toolbarTitleDisplayMode(router.isRootOfPath ? .inlineLarge : .inline)
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
