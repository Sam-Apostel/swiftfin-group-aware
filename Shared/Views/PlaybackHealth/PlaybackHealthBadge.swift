//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import JellyfinAPI
import SwiftUI

/// A small badge on the item page, shown only when the item is heavy for the server,
/// won't play well here, or stuttered before. Opens the details sheet.
struct PlaybackHealthBadge: View {

    @Default(.VideoPlayer.Playback.appMaximumBitrate)
    private var appMaximumBitrate
    @Default(.VideoPlayer.videoPlayerType)
    private var videoPlayerType

    @State
    private var isPresentingDetails = false
    @State
    private var verdict: PlaybackHealthVerdict?

    let item: BaseItemDto
    let mediaSource: MediaSourceInfo?

    private var taskID: String {
        [
            item.id ?? "",
            mediaSource?.id ?? "",
            String(appMaximumBitrate.rawValue),
            videoPlayerType.rawValue,
        ].joined(separator: "|")
    }

    private var title: String {
        guard let verdict, verdict.isBadgeWorthy else { return L10n.FourKReadiness.badge }

        return L10n.PlaybackHealth.badgeTitle(verdict)
    }

    private var is4K: Bool {
        let source = mediaSource ?? item.mediaSources?.first
        let video = source?.mediaStreams?.first { $0.type == .video }

        return TranscodeStreamClass.isFourK(width: video?.width ?? item.width, height: video?.height ?? item.height)
    }

    /// On Apple TV a 4K item always gets the badge: its sheet leads to "What it takes to watch 4K on this TV".
    private var showsFourKEntry: Bool {
        UIDevice.isTV && is4K
    }

    private var color: Color {
        guard let verdict, verdict.isBadgeWorthy else { return .secondary }

        return verdict.tier == .poor ? .red : .orange
    }

    var body: some View {
        ZStack {
            if let verdict, verdict.isBadgeWorthy || showsFourKEntry {
                Button {
                    isPresentingDetails = true
                } label: {
                    Label(title, systemImage: verdict.isBadgeWorthy ? "exclamationmark.triangle.fill" : "4k.tv")
                        .labelStyle(.attributeBadgeOutline)
                        .foregroundStyle(color)
                }
                .buttonStyle(.plain)
                .accessibilityHint(L10n.PlaybackHealth.details)
                .sheet(isPresented: $isPresentingDetails) {
                    PlaybackHealthDetailsView(verdict: verdict, is4K: is4K) {
                        isPresentingDetails = false
                    }
                }
            }
        }
        .task(id: taskID) {
            guard PlaybackHealthCheck.isEligible(item) else {
                verdict = nil
                return
            }

            verdict = await PlaybackHealthCheck.verdict(
                for: item,
                mediaSource: mediaSource,
                requestedBitrate: appMaximumBitrate
            )
        }
    }
}
