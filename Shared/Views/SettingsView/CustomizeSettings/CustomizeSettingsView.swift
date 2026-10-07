//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

/// Home & libraries: the home rows, how libraries look and filter, and on tvOS the tab bar.
struct CustomizeSettingsView: View {

    @Default(.Customization.Search.enabledDrawerFilters)
    private var searchEnabledDrawerFilters

    #if os(tvOS)
    @Default(.Customization.tabBarPlacement)
    private var tabBarPlacement
    #endif

    @Router
    private var router

    var body: some View {
        Form(systemImage: "house") {

            #if os(tvOS)
            Section(L10n.tabBar) {
                ListRowMenu(L10n.layout, selection: $tabBarPlacement)
            }
            #endif

            HomeSection()

            LibrarySection(isEmbedded: true)

            Section(L10n.search) {
                ChevronButton(L10n.filters) {
                    router.route(to: .itemFilterDrawerSelector(selection: $searchEnabledDrawerFilters))
                }
            }
        }
        .navigationTitle(L10n.CouchfinSettings.homeAndLibraries)
    }
}
