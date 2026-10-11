//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if os(tvOS)
import SwiftUI

extension DiscoverView {

    /// Opens the Seerr search screen. tvOS only: iOS searches from the navigation bar.
    struct SearchButton: View {

        @Router
        private var router

        var body: some View {
            Button {
                router.route(to: .seerrSearch)
            } label: {
                HStack(spacing: 24) {
                    Image(systemName: "magnifyingglass")
                        .font(.title3)
                        .frame(width: 70, height: 70)

                    Text(L10n.search)
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
                .padding(24)
                .padding(.trailing, 16)
            }
            .buttonStyle(.card)
        }
    }
}
#endif
