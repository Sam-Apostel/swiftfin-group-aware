//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import SwiftUI

extension ItemActionButtons {

    /// "For…": tag who the item is for on the audience watchlist.
    struct Audience: View {

        @EnvironmentObject
        private var provider: ItemContentGroupProvider

        @InjectedObject(\.audienceWatchlistStore)
        private var store: AudienceWatchlistStore

        @Router
        private var router

        @State
        private var error: Error?

        private var entry: AudienceWatchlistEntry? {
            AudienceWatchlistActions.entry(for: provider.item, in: store)
        }

        private var title: String {
            guard let entry else {
                return L10n.Audience.forEllipsis
            }

            return AudienceLabel.sentence(
                audience: entry.audience,
                users: AudienceWatchlistActions.serverUsers()
            )
        }

        private var systemImage: String {
            if entry == nil {
                ItemActionButton.audience.secondarySystemImage
            } else {
                ItemActionButton.audience.systemImage
            }
        }

        var body: some View {
            Button(title, systemImage: systemImage) {
                router.route(
                    to: .audiencePicker(item: provider.item) { result in
                        if case let .failure(failure) = result {
                            error = failure
                        }
                    }
                )
            }
            .isSelected(entry != nil)
            .errorMessage($error)
            .task {
                await AudienceWatchlistActions.refreshIfNeeded()
            }
        }
    }
}
