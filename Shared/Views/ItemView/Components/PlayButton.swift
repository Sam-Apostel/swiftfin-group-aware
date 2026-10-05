//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import JellyfinAPI
import Logging
import SwiftUI

struct PlayButton: View {

    @Default(.accentColor)
    private var accentColor

    @ObservedObject
    var provider: ItemContentGroupProvider

    @Router
    private var router

    @State
    private var isPresentingResumeChoice = false

    private var mediaSource: String? {
        guard provider.mediaPlayerItemProvider?.item.mediaSources?.count ?? 0 > 1 else { return nil }

        return provider.mediaPlayerItemProvider?.mediaSource?.displayTitle
    }

    /// On a group couch, when someone is at a point the primary user isn't at:
    /// Play asks whose resume point to start from.
    private var resumePlan: CouchResumePlan? {
        guard let plan = provider.couchResumePlan,
              plan.itemID == provider.mediaPlayerItemProvider?.item.id,
              plan.needsChoice
        else { return nil }

        return plan
    }

    /// "Sam is at 1:10:05"
    private var resumeHint: String? {
        guard let hint = resumePlan?.hint else { return nil }

        let names = ListFormatter.localizedString(byJoining: hint.names)

        return hint.names.count == 1
            ? L10n.CouchItem.isAt(names, time: hint.timecode)
            : L10n.CouchItem.areAt(names, time: hint.timecode)
    }

    /// The line under the Play label: the resume hint and/or the media source.
    private var subtitle: String? {
        switch (resumeHint, mediaSource) {
        case let (hint?, source?):
            "\(hint) · \(source)"
        case let (hint?, nil):
            hint
        case let (nil, source?):
            source
        case (nil, nil):
            nil
        }
    }

    /// - Parameter positionTicks: Where to start, or `nil` for the primary user's own resume point.
    private func play(positionTicks: Int? = nil) {
        let mediaPlayerItemProvider = if let positionTicks {
            provider.mediaPlayerItemProvider?.modifyingItem {
                if $0.userData == nil {
                    $0.userData = UserItemDataDto()
                }

                $0.userData?.playbackPositionTicks = positionTicks
            }
        } else {
            provider.mediaPlayerItemProvider
        }

        guard let mediaPlayerItemProvider else {
            provider.logger.error("Play selected with no playback item provider")
            return
        }

        let queue: (any MediaPlayerQueue)? = mediaPlayerItemProvider.item.type == .episode ?
            EpisodeMediaPlayerQueue(episode: mediaPlayerItemProvider.item) : nil

        router.route(
            to: .videoPlayer(
                provider: mediaPlayerItemProvider,
                queue: queue
            )
        )
    }

    @ViewBuilder
    private var label: some View {
        HStack {
            Image(systemName: "play.fill")

            VStack(spacing: 2) {
                Text(provider.mediaPlayerItemProvider?.item.playButtonLabel ?? L10n.play)

                if let subtitle {
                    Marquee(subtitle, speed: 40, delay: 3, fade: 5)
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
        }
        .font(.callout)
        .fontWeight(.semibold)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .backport
        .glassEffect(
            .regular.selection(
                tint: accentColor,
                foregroundColor: accentColor.overlayColor
            ),
            in: .capsule
        )
    }

    @ViewBuilder
    private var resumeChoices: some View {
        if let resumePlan {
            ForEach(resumePlan.points) { point in
                Button(
                    L10n.CouchItem.resumeFrom(
                        point.timecode,
                        names: point.names.joined(separator: ", ")
                    )
                ) {
                    play(positionTicks: point.ticks)
                }
            }
        }

        Button(L10n.CouchItem.startOver) {
            play(positionTicks: 0)
        }

        Button(L10n.cancel, role: .cancel) {}
    }

    var body: some View {
        Button {
            if resumePlan != nil {
                isPresentingResumeChoice = true
            } else {
                play()
            }
        } label: {
            label
        }
        .buttonBorderShape(.capsule)
        .buttonStyle(BasicHoverButtonStyle())
        .contextMenu {
            if provider.mediaPlayerItemProvider?.item.userData?.playbackPositionTicks != 0 {
                Button(L10n.playFromBeginning, systemImage: "gobackward") {
                    play(positionTicks: 0)
                }
            }
        }
        .confirmationDialog(
            L10n.CouchItem.whereToStart,
            isPresented: $isPresentingResumeChoice,
            titleVisibility: .visible
        ) {
            resumeChoices
        }
        .disabled(provider.mediaPlayerItemProvider == nil)
    }
}
