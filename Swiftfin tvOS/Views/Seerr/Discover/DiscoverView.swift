//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import SwiftUI

/// The tvOS Discover tab.
///
/// Until Seerr works on this Apple TV it shows a setup state (adopting the household's
/// server, connecting, signing the couch in with Quick Connect). Then it shows a
/// `ContentGroupView` of `SeerrDiscoverContentGroupProvider`, like Home.
struct DiscoverView: View {

    @InjectedObject(\.seerrService)
    private var seerrService: SeerrService

    @StateObject
    private var viewModel = SeerrTVSetupViewModel()

    @TabItemSelected
    private var tabItemSelected

    init() {}

    /// Changes whenever Seerr is connected, disconnected or reconfigured, so the rows are rebuilt.
    private var clientIdentity: ObjectIdentifier? {
        seerrService.client.map { ObjectIdentifier($0) }
    }

    @ViewBuilder
    private var contentView: some View {
        switch viewModel.phase {
        case .checking:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .needsServer:
            NoServerView(viewModel: viewModel)

        case .needsSignIn, .signingIn:
            SignInView(viewModel: viewModel)

        case .ready:
            ContentGroupView(provider: SeerrDiscoverContentGroupProvider())
                .id(clientIdentity)
                .onAppear {
                    viewModel.signInRemainingCouchSilently()
                }
        }
    }

    var body: some View {
        ZStack {
            contentView
        }
        .animation(.linear(duration: 0.2), value: viewModel.phase)
        .onFirstAppear {
            Task {
                await viewModel.start()
            }
        }
        .onChange(of: viewModel.phase) {
            if viewModel.phase == .ready {
                viewModel.signInRemainingCouchSilently()
            }
        }
        .onSceneWillEnterForeground {
            checkAgainIfNeeded()
        }
        .onReceive(tabItemSelected) { _ in
            checkAgainIfNeeded()
        }
    }

    /// "Not set up" updates by itself: Seerr may have been connected on the iPhone meanwhile.
    private func checkAgainIfNeeded() {
        guard viewModel.shouldCheckAgain else { return }

        Task {
            await viewModel.start()
        }
    }
}
