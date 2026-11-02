//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Foundation
import JellyfinAPI

extension Defaults.Keys.VideoPlayer {

    /// tvOS: open HDR and Dolby Vision videos in the native player, the only one that sends HDR to the TV.
    static var nativePlayerForHDR: Defaults.Key<Bool> {
        Defaults.Key("videoPlayerNativeForHDR", default: true, suite: .currentUserSuite)
    }
}

extension VideoPlayerType {

    /// The player of the playback that's open when it differs from the setting. Set when the player opens.
    static var playbackOverride: VideoPlayerType?

    /// The player of the playback that's open, or the setting.
    static var current: VideoPlayerType {
        playbackOverride ?? Defaults[.VideoPlayer.videoPlayerType]
    }

    /// Whether this player sends HDR10 and Dolby Vision to the TV. VLC and mpv show HDR as SDR on Apple TV,
    /// and only the native player switches the TV's mode with Match Content.
    var keepsHDR: Bool {
        self == .avPlayer
    }

    /// The player to open a video with: the native player for an HDR or Dolby Vision video when that setting is on
    /// and the screen shows HDR, otherwise the chosen player.
    static func forPlayback(
        chosen: VideoPlayerType,
        prefersNativeForHDR: Bool,
        displaysHDR: Bool,
        isHDRVideo: Bool
    ) -> VideoPlayerType {
        guard prefersNativeForHDR, displaysHDR, isHDRVideo else { return chosen }

        return .avPlayer
    }

    /// The player to open `item` with on this device.
    static func forPlayback(of item: BaseItemDto) -> VideoPlayerType {
        let chosen = Defaults[.VideoPlayer.videoPlayerType]

        #if os(tvOS)
        let streams = item.mediaSources?.first?.mediaStreams ?? item.mediaStreams ?? []
        let isHDRVideo = streams.contains { $0.type == .video && $0.videoRangeType?.isHDR == true }

        return forPlayback(
            chosen: chosen,
            prefersNativeForHDR: Defaults[.VideoPlayer.nativePlayerForHDR],
            displaysHDR: PlaybackCapabilities.isDeviceHDRCapable,
            isHDRVideo: isHDRVideo
        )
        #else
        return chosen
        #endif
    }
}
