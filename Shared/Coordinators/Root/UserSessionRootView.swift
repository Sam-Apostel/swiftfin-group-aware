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

struct UserSessionRootView: View {

    @Environment(\.localUserAuthenticationAction)
    private var authenticationAction

    @InjectedObject(\.userSessionManager)
    private var userSessionManager

    private var sessionViewID: String? {
        guard let currentSession = userSessionManager.currentSession else { return nil }

        return "\(currentSession.user.id)-\(currentSession.couch.id)"
    }

    var body: some View {
        ZStack {
            switch userSessionManager.state {
            case .initial:
                ProgressView()

            case .signedOut:
                NavigationInjectionView(coordinator: .init()) {
                    SelectUserView()
                }
                #if os(iOS)
                // "Vote for tonight" also reaches a phone that sits on the couch picker
                // (MainTabView has its own prompt while signed in)
                .couchVotePrompt()
                #endif

            case .signedIn:
                PosterPreferencesEnvironment {
                    MainTabView()
                }
                // Rebuild tabs and home whenever the people on the couch change,
                // or the couch browses as another member (same people, new primary)
                .id(sessionViewID)
            }
        }
        .animation(.linear(duration: 0.1), value: userSessionManager.state)
        .task {
            await userSessionManager.start()
        }
        .onOpenURL { url in
            guard let authenticationAction else { return }

            Task {
                await userSessionManager.handleOpenURL(
                    url,
                    authenticationAction: authenticationAction
                )
            }
        }
    }
}

private struct PosterPreferencesEnvironment<Content: View>: View {

    @Default(.Customization.Poster.configuration)
    private var posterConfiguration

    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .environment(\.posterConfiguration, posterConfiguration)
    }
}
