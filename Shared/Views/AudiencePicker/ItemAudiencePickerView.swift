//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import JellyfinAPI
import SwiftUI

/// The audience picker for a Jellyfin library item.
///
/// Items coming from lists usually lack `providerIDs`, so the full item is fetched first:
/// the TMDB id decides the watchlist entry id (`tmdb-movie-862`), which keeps tags made
/// here and in Seerr on the same entry.
struct ItemAudiencePickerView: View {

    @Injected(\.currentUserSession)
    private var userSession: UserSession?

    @State
    private var resolvedItem: BaseItemDto?

    private let item: BaseItemDto
    private let completion: ((Result<AudienceWatchlistActions.Outcome, Error>) -> Void)?

    init(
        item: BaseItemDto,
        completion: ((Result<AudienceWatchlistActions.Outcome, Error>) -> Void)? = nil
    ) {
        self.item = item
        self.completion = completion

        // A full item (e.g. from the item view) already has its provider ids
        self._resolvedItem = State(initialValue: item.providerIDs == nil ? nil : item)
    }

    /// Fetches the full item and refreshes the watchlist at the same time.
    private func resolve() async {
        async let fetchedItem: BaseItemDto? = fetchFullItem()
        async let refresh: Void = AudienceWatchlistActions.refreshIfNeeded()

        let fullItem = await fetchedItem
        await refresh

        resolvedItem = fullItem ?? item
    }

    private func fetchFullItem() async -> BaseItemDto? {
        guard let userSession else { return nil }

        return try? await item.getFullItem(userSession: userSession)
    }

    @ViewBuilder
    private func picker(for item: BaseItemDto) -> some View {
        let entry = AudienceWatchlistActions.entry(for: item)

        AudiencePickerView(
            title: item.displayTitle,
            initialAudience: AudienceWatchlistActions.initialAudience(for: item),
            isExisting: entry != nil
        ) { audience in
            AudienceWatchlistActions.perform(.saved(audience), item: item, completion: completion)
        } onRemove: {
            AudienceWatchlistActions.perform(.removed, item: item, completion: completion)
        }
    }

    var body: some View {
        if let resolvedItem {
            picker(for: resolvedItem)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task {
                    await resolve()
                }
        }
    }
}

/// "For Sam & Lisa" under the item view's action bar, when the item is on the audience watchlist.
struct ItemAudienceLabel: View {

    @InjectedObject(\.audienceWatchlistStore)
    private var store: AudienceWatchlistStore

    let item: BaseItemDto

    var body: some View {
        if AudienceWatchlistActions.supports(item),
           let entry = AudienceWatchlistActions.entry(for: item, in: store),
           entry.audience.isNotEmpty
        {
            AudienceLabel(
                audience: entry.audience,
                users: AudienceWatchlistActions.serverUsers()
            )
            .foregroundStyle(.secondary)
            .transition(.opacity)
        }
    }
}
