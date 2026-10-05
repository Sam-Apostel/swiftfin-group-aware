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

/// The couch's language pick for the item that Play would start, e.g.
/// "Dutch audio · no subtitles — Tuur is on the couch".
///
/// Shown under the audience label in `ItemView.ActionBar`, only for a group couch
/// when `CouchLanguages.decision` has something to decide. It uses the same inputs
/// as `MediaPlayerItem.build`, including the user's explicit Playback menu picks,
/// so the label always matches what will play. The label is plain text, so it never
/// takes tvOS focus.
struct CouchLanguageLabel: View {

    @Injected(\.currentUserSession)
    private var userSession: UserSession?

    @InjectedObject(\.couchLanguageStore)
    private var store: CouchLanguageStore

    @ObservedObject
    var provider: ItemContentGroupProvider

    init(provider: ItemContentGroupProvider) {
        self.provider = provider
    }

    private var decision: CouchLanguageDecision? {
        // Read `revision` so edits made in Couch settings re-render the label.
        _ = store.revision

        guard let itemProvider = provider.mediaPlayerItemProvider,
              let mediaSource = itemProvider.mediaSource
        else { return nil }

        return CouchLanguages.decision(
            for: mediaSource,
            item: itemProvider.item,
            audioStreamIndex: itemProvider.audioStreamIndex,
            subtitleStreamIndex: itemProvider.subtitleStreamIndex
        )
    }

    private var font: Font {
        UIDevice.isTV ? .caption : .callout
    }

    var body: some View {
        if let summary = decision?.summary {
            Label {
                Text(summary)
            } icon: {
                Image(systemName: "sofa.fill")
            }
            .font(font)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .accessibilityElement(children: .combine)
            .transition(.opacity)
            .task(id: userSession?.couch.id) {
                await refreshProfiles()
            }
        }
    }

    /// Refreshes every member's language profile in the background (throttled in the store),
    /// so the playback hook reads fresh preferences when Play is pressed.
    private func refreshProfiles() async {
        guard let userSession, userSession.couch.isGroup else { return }

        await store.refreshIfNeeded(couch: userSession.couch, in: userSession)
    }
}
