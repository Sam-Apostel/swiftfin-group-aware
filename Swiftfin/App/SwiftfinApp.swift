//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import PreferencesView
import SwiftUI
import UIKit

@main
struct SwiftfinApp: App {

    init() {
        Self.configure()

        UIScrollView.appearance().keyboardDismissMode = .onDrag

        // Sometimes the tab bar won't appear properly on push, always have material background.
        UITabBar.appearance().scrollEdgeAppearance = UITabBarAppearance(idiom: .unspecified)

        // Couchfin's voice: rounded titles
        let navigationBar = UINavigationBar.appearance()
        navigationBar.largeTitleTextAttributes = [
            .font: UIFont.couchfinRounded(size: 34, weight: .heavy, relativeTo: .largeTitle),
        ]
        navigationBar.titleTextAttributes = [
            .font: UIFont.couchfinRounded(size: 17, weight: .bold, relativeTo: .headline),
        ]

        SwiftfinSpotlight().addSwiftfinToSpotlight()
    }

    var body: some Scene {
        WindowGroup {
            OverlayToastView {
                PreferencesView {
                    WithLocalUserAuthentication {
                        RootView()
                            .supportedOrientations(UIDevice.isPad ? .allButUpsideDown : .portrait)
                    }
                }
            }
            .ignoresSafeArea()
        }
    }
}

extension UINavigationController {

    // Remove back button text
    override open func viewWillLayoutSubviews() {
        navigationBar.topItem?.backButtonDisplayMode = .minimal
    }
}
