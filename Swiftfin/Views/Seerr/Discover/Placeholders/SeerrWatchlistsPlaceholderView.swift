//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import SwiftUI

// TODO: #15 replaces `NavigationRoute.seerrWatchlists` with `WatchlistsView`; delete this file then.

/// A minimal list of the couch watchlist, used by `NavigationRoute.seerrWatchlists`
/// until the grouped watchlists screen (#15) lands.
struct SeerrWatchlistsPlaceholderView: View {

    @InjectedObject(\.audienceWatchlistStore)
    private var watchlistStore

    @Router
    private var router

    private func open(_ entry: AudienceWatchlistEntry) {
        if let tmdbID = entry.tmdbID {
            let mediaType: SeerrMediaType = switch entry.kind {
            case .movie:
                .movie
            case .tv:
                .tv
            }

            router.route(to: .seerrMedia(mediaType: mediaType, tmdbID: tmdbID))
        } else if let itemID = entry.jellyfinItemID {
            router.route(to: .item(id: itemID))
        }
    }

    private func row(_ entry: AudienceWatchlistEntry) -> some View {
        Button {
            open(entry)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.body)
                    .foregroundStyle(.primary)

                if let year = entry.year {
                    Text(String(year))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.primary, .secondary)
    }

    var body: some View {
        List {
            ForEach(watchlistStore.entries) { entry in
                row(entry)
            }
        }
        .overlay {
            if watchlistStore.entries.isEmpty, !watchlistStore.isRefreshing {
                ContentUnavailableView(
                    L10n.SeerrDiscover.ourWatchlists,
                    systemImage: "sofa",
                    description: Text(L10n.SeerrDiscover.watchlistsEmpty)
                )
            }
        }
        .navigationTitle(L10n.SeerrDiscover.ourWatchlists)
        .toolbarTitleDisplayMode(.inline)
        .refreshable {
            await watchlistStore.refreshFromCurrentSession()
        }
    }
}
