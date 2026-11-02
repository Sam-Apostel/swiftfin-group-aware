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
        guard let verdict else { return "" }

        switch verdict.tier {
        case .poor:
            return L10n.PlaybackHealth.badgePoor
        case .heavy:
            return L10n.PlaybackHealth.badgeHeavy
        case .direct, .light:
            return L10n.PlaybackHealth.badgeStalled
        }
    }

    var body: some View {
        ZStack {
            if let verdict, verdict.isBadgeWorthy {
                Button {
                    isPresentingDetails = true
                } label: {
                    Label(title, systemImage: "exclamationmark.triangle.fill")
                        .labelStyle(.attributeBadgeOutline)
                        .foregroundStyle(verdict.tier == .poor ? Color.red : Color.orange)
                }
                .buttonStyle(.plain)
                .accessibilityHint(L10n.PlaybackHealth.details)
                .sheet(isPresented: $isPresentingDetails) {
                    PlaybackHealthDetailsView(verdict: verdict) {
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
