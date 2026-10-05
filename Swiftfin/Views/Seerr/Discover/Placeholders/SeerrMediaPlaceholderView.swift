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

// TODO: #14 replaces `NavigationRoute.seerrMedia` with `SeerrMediaDetailView`; delete this file then.

/// A minimal Seerr title screen used by `NavigationRoute.seerrMedia` until the full detail view (#14) lands.
struct SeerrMediaPlaceholderView: View {

    @Default(.accentColor)
    private var accentColor

    @InjectedObject(\.seerrService)
    private var seerrService

    @Router
    private var router

    @State
    private var details: SeerrMediaDetails?
    @State
    private var error: Error?

    let mediaType: SeerrMediaType
    let tmdbID: Int

    private func load() async {
        guard let client = seerrService.client else {
            error = SeerrError.notConfigured
            return
        }

        do {
            details = try await client.details(mediaType: mediaType, tmdbID: tmdbID)
            error = nil
        } catch {
            if details == nil {
                self.error = error
            }
        }
    }

    @ViewBuilder
    private func playButton(itemID: String) -> some View {
        Button {
            router.route(to: .item(id: itemID))
        } label: {
            Label(L10n.play, systemImage: "play.fill")
                .frame(maxWidth: .infinity)
        }
        .fontWeight(.semibold)
        .backport
        .buttonStyle(.glassProminent.shadow(false))
        .tint(accentColor)
        .controlSize(.large)
        .frame(maxWidth: 300)
    }

    @ViewBuilder
    private func content(_ details: SeerrMediaDetails) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                PosterImage(
                    item: details.media,
                    type: .portrait,
                    size: .medium
                )
                .frame(width: 180)
                .subtleShadow()

                Text(details.title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)

                DotHStack {
                    if let year = details.year {
                        Text(String(year))
                    }

                    Text(details.status.displayTitle)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                if details.status.isAvailable, let itemID = details.jellyfinItemID {
                    playButton(itemID: itemID)
                }

                if let overview = details.overview {
                    Text(overview)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .edgePadding()
        }
    }

    var body: some View {
        ZStack {
            if let details {
                content(details)
            } else if let error {
                ErrorView(error: error)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(details?.title ?? String.space)
        .toolbarTitleDisplayMode(.inline)
        .task {
            await load()
        }
        .refreshable {
            await load()
        }
    }
}
