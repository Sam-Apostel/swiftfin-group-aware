//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import FactoryKit
import Foundation
import JellyfinAPI
import SwiftUI

struct ContentGroupView<Provider: ContentGroupProvider>: View {

    private enum Focus: String {
        case content = "contentGroup-content"
    }

    @Environment(\.tabSafeAreaInsets)
    private var tabSafeAreaInsets

    @Router
    private var router

    @State
    private var contentGroupOptions: ContentGroupParentOption = .init()

    @StateObject
    private var focusCoordinator = FocusCoordinator(waitingFor: Focus.content.rawValue, focusPlaceholder: true)
    @StateObject
    private var viewModel: ContentGroupViewModel<Provider>

    @TabItemSelected
    private var tabItemSelected

    init(provider: Provider) {
        _viewModel = StateObject(wrappedValue: ContentGroupViewModel(provider: provider))
    }

    @ViewBuilder
    private var contentView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: 0)
                        .id("top")

                    ContentGroupVStack(groups: viewModel.groups)
                        .edgePadding(contentGroupOptions.contains(.ignoreSafeAreaTop) ? .bottom : .vertical)
                        .padding(.top, contentGroupOptions.contains(.ignoreSafeAreaTop) ? 0 : tabSafeAreaInsets.top)
                        .onPreferenceChange(ContentGroupCustomizationKey.self) { value in
                            contentGroupOptions = value
                        }

                    // More groups are on their way (`ContentGroupProvider.revealsProgressively`)
                    if viewModel.state == .refreshing {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 40)
                    }
                }
            }
            .trackingFrame(for: .scrollView)
            #if os(tvOS)
            .coordinatedFocus(Focus.content.rawValue)
            .ignoresSafeArea(.container, edges: [.horizontal, .top])
            #else
            .ignoresSafeArea(
                edges: contentGroupOptions.contains(.ignoreSafeAreaTop) ? [.horizontal, .top] : .horizontal
            )
            #endif
            .scrollIndicators(.hidden)
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

    /// Whether the groups are shown: once loaded, and while they load when the provider reveals them
    /// progressively (`ContentGroupProvider.revealsProgressively`).
    ///
    /// The groups stay in the same branch of `body` from the first group shown until the refresh ends,
    /// so the scroll position and the tvOS focus are kept when the state becomes `.content`.
    private var showsGroups: Bool {
        guard viewModel.groups.isNotEmpty else { return false }

        switch viewModel.state {
        case .content:
            return true
        case .refreshing:
            return viewModel.provider.revealsProgressively
        case .error, .initial:
            return false
        }
    }

    @ViewBuilder
    private var stateView: some View {
        switch viewModel.state {
        case .content:
            ContentUnavailableView(
                L10n.noResults.localizedCapitalized,
                systemImage: "rectangle.on.rectangle.slash"
            )
            .focusable()
            #if os(tvOS)
            .coordinatedFocus(.fallback)
            #endif

        case .error:
            viewModel.error.map(ErrorView.init)
                #if os(tvOS)
                    .coordinatedFocus(.fallback)
                #endif

        case .initial, .refreshing:
            ProgressView()
                #if os(tvOS)
                    .coordinatedFocus(.placeholder)
                #endif
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(edges: .all)
        }
    }

    var body: some View {
        ZStack {
            if showsGroups {
                contentView
            } else {
                stateView
            }
        }
        .animation(.linear(duration: 0.2), value: viewModel.state)
        .animation(.linear(duration: 0.2), value: viewModel.background.states)
        .navigationTitle(viewModel.provider.displayTitle)
        #if os(iOS)
        .toolbarTitleDisplayMode(router.isRootOfPath ? .inlineLarge : .inline)
        #elseif os(tvOS)
        .toolbar(router.isRootOfPath ? .hidden : .automatic, for: .navigationBar)
        #endif
        .onFirstAppear {
            viewModel.refresh()
        }
        .refreshable {
            viewModel.refresh()
        }
        .sinceLastDisappear { interval in
            viewModel.refreshIfNeeded(sinceLastDisappear: interval)
        }
        .onSceneWillEnterForeground {
            viewModel.refreshIfPendingChanges()
            viewModel.refreshCouchPicksIfStale()
        }
        .task {
            await viewModel.refreshCouchPicksWhileVisible()
        }
        .topBarTrailing {
            if #unavailable(iOS 26.0) {
                if viewModel.background.is(.refreshing) {
                    ProgressView()
                }
            }
        }
        .environmentObject(focusCoordinator)
    }
}
