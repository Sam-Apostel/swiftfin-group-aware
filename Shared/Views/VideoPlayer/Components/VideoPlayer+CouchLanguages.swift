//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension View {

    /// Shows the couch's language pick as an overlay toast when a new item starts,
    /// e.g. "Dutch audio · no subtitles — Tuur is on the couch".
    ///
    /// - Only items built with a couch decision announce. Rebuilds after a track or
    ///   bitrate change carry no decision, so they stay silent.
    /// - A summary is only announced again when it differs from the last one
    ///   announced in this player, so autoplaying a series doesn't repeat it every episode.
    func couchLanguageAnnouncements(manager: MediaPlayerManager, toastProxy: ToastProxy) -> some View {
        modifier(
            CouchLanguageAnnouncementModifier(
                manager: manager,
                toastProxy: toastProxy
            )
        )
    }
}

private struct CouchLanguageAnnouncementModifier: ViewModifier {

    @State
    private var lastSummary: String? = nil

    private let manager: MediaPlayerManager
    private let toastProxy: ToastProxy

    init(manager: MediaPlayerManager, toastProxy: ToastProxy) {
        self.manager = manager
        self.toastProxy = toastProxy
    }

    func body(content: Content) -> some View {
        content
            .onReceive(manager.$playbackItem) { newItem in
                guard let summary = newItem?.couchLanguageDecision?.summary,
                      summary != lastSummary
                else { return }

                lastSummary = summary
                toastProxy.present(summary, systemName: "sofa.fill")
            }
    }
}
