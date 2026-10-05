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

extension DiscoverView {

    /// Entry card to the "Our watchlists" screen (#15), with a count for the current couch.
    struct WatchlistsCard: View {

        @Default(.accentColor)
        private var accentColor

        @Injected(\.currentUserSession)
        private var userSession

        @InjectedObject(\.audienceWatchlistStore)
        private var watchlistStore

        @Router
        private var router

        private var couchMembers: [UserState] {
            userSession?.couch.members ?? []
        }

        private var couchCount: Int {
            guard let couch = userSession?.couch else { return 0 }

            return watchlistStore.entries(forExactAudience: couch.memberIDs).count
        }

        private var totalCount: Int {
            watchlistStore.entries.count
        }

        private var subtitle: String {
            if totalCount == 0 {
                L10n.SeerrDiscover.watchlistsEmpty
            } else {
                L10n.SeerrDiscover.watchlistsSummary(
                    couchCount: couchCount,
                    totalCount: totalCount
                )
            }
        }

        private var icon: some View {
            Image(systemName: "sofa.fill")
                .font(.title3)
                .foregroundStyle(accentColor.overlayColor)
                .frame(width: 44, height: 44)
                .background(accentColor, in: .circle)
        }

        @ViewBuilder
        private var avatars: some View {
            if let userSession, couchMembers.count > 1 {
                HStack(spacing: -10) {
                    ForEach(couchMembers.prefix(4), id: \.id) { member in
                        UserProfileImage(
                            userID: member.id,
                            source: member.profileImageSource(client: userSession.client),
                            pipeline: .Swiftfin.local
                        )
                        .frame(width: 28, height: 28)
                    }
                }
            }
        }

        var body: some View {
            Button {
                router.route(to: .seerrWatchlists)
            } label: {
                HStack(spacing: 12) {
                    icon

                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.SeerrDiscover.ourWatchlists)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    avatars

                    Image(systemName: "chevron.forward")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.secondarySystemBackground)
                }
                .contentShape(.rect(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
        }
    }
}
