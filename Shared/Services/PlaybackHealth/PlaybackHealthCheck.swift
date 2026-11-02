//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import FactoryKit
import Foundation
import JellyfinAPI

extension PlaybackHealthDevice {

    /// The capabilities of this device and screen, honoring the "force DV/HDR transcode" settings.
    static var current: PlaybackHealthDevice {
        PlaybackHealthDevice(
            supportsHEVC: PlaybackCapabilities.supportsHEVC,
            supportsHDR: PlaybackCapabilities.isDeviceHDRCapable && PlaybackCapabilities.supportsHDR10,
            supportsDolbyVision: PlaybackCapabilities.isDeviceHDRCapable && PlaybackCapabilities.supportsDolbyVision
        )
    }
}

/// Asks the server how it would play an item on this device, before pressing play.
@MainActor
enum PlaybackHealthCheck {

    /// The server's decisions, keyed by item, media source, player and bitrate.
    private static var decisions: [String: MediaSourceInfo] = [:]

    /// Items the verdict is shown for: things with a video file.
    static func isEligible(_ item: BaseItemDto) -> Bool {
        guard !item.isLiveStream else { return false }

        switch item.type {
        case .episode, .movie, .musicVideo, .video:
            return true
        default:
            return false
        }
    }

    /// The bitrate limit chosen in settings, `nil` for automatic or maximum.
    static func maxBitrate(for requestedBitrate: PlaybackBitrate) -> Int? {
        switch requestedBitrate {
        case .auto, .max:
            nil
        default:
            requestedBitrate.rawValue
        }
    }

    /// The verdict for an item, using the server's PlaybackInfo when it answers and the file's facts otherwise.
    static func verdict(
        for item: BaseItemDto,
        mediaSource: MediaSourceInfo?,
        requestedBitrate: PlaybackBitrate = Defaults[.VideoPlayer.Playback.appMaximumBitrate]
    ) async -> PlaybackHealthVerdict? {
        guard isEligible(item),
              let itemID = item.id,
              let mediaSource = mediaSource ?? item.mediaSources?.first
        else { return nil }

        let videoPlayerType = Defaults[.VideoPlayer.videoPlayerType]
        let compatibilityMode = Defaults[.VideoPlayer.Playback.compatibilityMode]
        let bitrateLimit = Self.maxBitrate(for: requestedBitrate)

        let deviceProfile = DeviceProfile.build(
            for: videoPlayerType,
            compatibilityMode: compatibilityMode,
            maxBitrate: bitrateLimit
        )

        let key = [
            itemID,
            mediaSource.id ?? "",
            videoPlayerType.rawValue,
            compatibilityMode.rawValue,
            String(bitrateLimit ?? 0),
        ].joined(separator: "|")

        var decision = decisions[key]

        if decision == nil, let userSession = Container.shared.currentUserSession() {
            var playbackInfo = PlaybackInfoDto()
            playbackInfo.deviceProfile = deviceProfile
            playbackInfo.isAutoOpenLiveStream = false
            playbackInfo.maxStreamingBitrate = bitrateLimit
            playbackInfo.mediaSourceID = mediaSource.id
            playbackInfo.userID = userSession.user.id

            let request = Paths.getPostedPlaybackInfo(itemID: itemID, playbackInfo)

            if let response = try? await userSession.client.send(request) {
                let sources = response.value.mediaSources ?? []
                decision = sources.first { $0.id == mediaSource.id } ?? sources.first
                decisions[key] = decision
            }
        }

        let input = PlaybackHealthInput(
            mediaSource: decision ?? mediaSource,
            isServerDecision: decision != nil,
            deviceProfile: deviceProfile,
            device: .current,
            maxBitrate: bitrateLimit,
            stalledBefore: PlaybackHealthMemory.stalls(for: itemID)
        )

        return PlaybackHealthClassifier.verdict(for: input)
    }
}
