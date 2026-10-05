//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension DiscoverView {

    /// A horizontal poster row in the house style; the header opens the paged "see all" grid.
    struct RowSection: View {

        @Router
        private var router

        let row: DiscoverViewModel.Row

        private func routeToLibrary() {
            router.route(to: .library(library: SeerrDiscoverLibrary(category: row.category)))
        }

        private var header: some View {
            Button(action: routeToLibrary) {
                HStack(spacing: 3) {
                    Text(row.category.displayTitle)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .lineLimit(1)

                    Image(systemName: "chevron.forward")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary, .secondary)
            .accessibilityAction(named: Text(L10n.openLibrary), routeToLibrary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        var body: some View {
            ContentGroupSection {
                PosterHStack(
                    elements: row.items,
                    displayType: .portrait,
                    size: .small
                ) { media, namespace in
                    media.libraryDidSelectElement(router: router, in: namespace)
                }
            } header: {
                header
                    .edgePadding(.horizontal)
                    .accessibilityAddTraits(.isHeader)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(row.category.displayTitle)
        }
    }
}
