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

        /// On tvOS this button may sit in the action bar's "…" menu, where its own alert never shows:
        /// without a completion, a failed save is shown by the app-wide alert instead.
        private var completion: ((Result<AudienceWatchlistActions.Outcome, Error>) -> Void)? {
            #if os(tvOS)
            return nil
            #else
            return { result in
                if case let .failure(failure) = result {
                    error = failure
                }
            }
            #endif
        }

        var body: some View {
            Button(title, systemImage: systemImage) {
                router.route(
                    to: .audiencePicker(item: provider.item, completion: completion)
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
