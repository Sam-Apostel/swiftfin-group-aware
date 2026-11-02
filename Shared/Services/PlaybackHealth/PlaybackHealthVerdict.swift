//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

// MARK: - Tier

/// How much work the server has to do to play an item on this device.
enum PlaybackHealthTier: Int, Comparable {

    /// The file is sent as is.
    case direct
    /// The server only converts the audio, the subtitles or the container. Cheap.
    case light
    /// The server re-encodes the video. May stutter on a small server.
    case heavy
    /// Re-encoding a 4K or HDR video, or no way to play it at all.
    case poor

    static func < (lhs: PlaybackHealthTier, rhs: PlaybackHealthTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Device

/// What this device can decode and show, independent of UIKit so the classifier stays pure.
struct PlaybackHealthDevice: Equatable {

    var supportsHEVC: Bool
    var supportsHDR: Bool
    var supportsDolbyVision: Bool
}

// MARK: - Reason

/// Why an item needs work from the server, in terms a viewer can understand.
enum PlaybackHealthReason: Hashable {

    /// Dolby Vision this device can't show, with the profile when known.
    case dolbyVision(profile: Int?)
    /// HDR video converted to SDR for this screen.
    case hdrConversion
    /// The video codec, profile, level or bit depth isn't playable here.
    case videoFormat(String)
    /// The video is larger than the maximum resolution setting.
    case videoResolution
    /// Image subtitles (PGS, VobSub) burned into the video.
    case imageSubtitles(String)
    /// The video's bitrate is above the quality setting, so the server shrinks it.
    case bitrateLimit(sourceMbps: Int, limitMbps: Int?)
    /// Only the audio is converted.
    case audioFormat(String)
    /// Only the container is repackaged.
    case container(String)
    /// Text subtitles converted to a format the player understands.
    case subtitleConversion
    /// The server converts the item without saying why.
    case unknownConversion
    /// A direct play with high bitrate peaks, which can be too much for Wi-Fi.
    case highBitrate(mbps: Int)
    /// The server can't play it directly and can't convert it either.
    case noPlayablePath

    /// Whether the reason means the server re-encodes the video.
    var isVideoReencode: Bool {
        switch self {
        case .bitrateLimit, .dolbyVision, .hdrConversion, .imageSubtitles, .videoFormat, .videoResolution:
            true
        case .audioFormat, .container, .highBitrate, .noPlayablePath, .subtitleConversion, .unknownConversion:
            false
        }
    }
}

// MARK: - Target

/// A copy of the item that would play directly on this device.
struct PlaybackHealthTarget: Equatable {

    /// 2160 for 4K, 1080 for 1080p, or the source height when smaller.
    var height: Int
    var isHEVC: Bool
    var isHDR: Bool
    var convertsAudio: Bool
    var usesTextSubtitles: Bool
    var maxMbps: Int?
}

// MARK: - Verdict

struct PlaybackHealthVerdict: Equatable {

    var tier: PlaybackHealthTier
    var reasons: [PlaybackHealthReason]
    var target: PlaybackHealthTarget?

    /// Rebuffering stalls remembered for this item on this device.
    var stalledBefore: Int = 0

    /// Only heavy work, bad prospects, or a stutter history earn a badge on the item page.
    var isBadgeWorthy: Bool {
        tier >= .heavy || stalledBefore >= PlaybackHealthClassifier.stallsWorthReporting
    }
}

// MARK: - Input

struct PlaybackHealthInput {

    /// The media source, ideally from a PlaybackInfo response built with this device's profile.
    var mediaSource: MediaSourceInfo
    /// Whether `mediaSource` carries the server's decision (PlaybackInfo) or only the file's facts.
    var isServerDecision: Bool
    var deviceProfile: DeviceProfile
    var device: PlaybackHealthDevice
    /// The bitrate limit chosen in settings, `nil` for no limit.
    var maxBitrate: Int?
    var audioStreamIndex: Int?
    var subtitleStreamIndex: Int?
    var stalledBefore: Int = 0
}

// MARK: - Classifier

/// Pure classification of how well an item will play. No UIKit, no networking.
enum PlaybackHealthClassifier {

    /// Direct plays above this bitrate get a Wi-Fi note.
    static let highBitrateWarning = 40_000_000
    /// Re-encoding above this height is too much for a small server.
    static let heavyHeightLimit = 1440
    /// Sessions with at least this many stalls are reported.
    static let stallsWorthReporting = 2

    private static let videoFormatReasons: Set<TranscodeReason> = [
        .videoCodecNotSupported,
        .videoProfileNotSupported,
        .videoLevelNotSupported,
        .videoBitDepthNotSupported,
        .videoFramerateNotSupported,
        .refFramesNotSupported,
        .anamorphicVideoNotSupported,
        .interlacedVideoNotSupported,
        .videoCodecTagNotSupported,
        .videoRotationNotSupported,
        .unknownVideoStreamInfo,
    ]

    private static let bitrateReasons: Set<TranscodeReason> = [
        .containerBitrateExceedsLimit,
        .videoBitrateNotSupported,
    ]

    private static let audioReasons: Set<TranscodeReason> = [
        .audioCodecNotSupported,
        .audioIsExternal,
        .secondaryAudioNotSupported,
        .audioChannelsNotSupported,
        .audioProfileNotSupported,
        .audioSampleRateNotSupported,
        .audioBitDepthNotSupported,
        .audioBitrateNotSupported,
        .unknownAudioStreamInfo,
    ]

    private static let containerReasons: Set<TranscodeReason> = [
        .containerNotSupported,
        .directPlayError,
        .streamCountExceedsLimit,
    ]

    static func verdict(for input: PlaybackHealthInput) -> PlaybackHealthVerdict {
        let source = input.mediaSource
        let streams = source.mediaStreams ?? []
        let video = streams.first { $0.type == .video }
        let audio = selectedStream(of: .audio, index: input.audioStreamIndex ?? source.defaultAudioStreamIndex, in: streams)
        let subtitle = selectedStream(of: .subtitle, index: input.subtitleStreamIndex ?? source.defaultSubtitleStreamIndex, in: streams)

        let transcodeReasons: Set<TranscodeReason>
        let isConverted: Bool
        let isBurningSubtitles: Bool
        var hasPlayablePath = true

        if input.isServerDecision {
            transcodeReasons = Self.transcodeReasons(in: source.transcodingURL)
            isConverted = source.transcodingURL != nil
            isBurningSubtitles = isConverted && subtitle?.deliveryMethod == .encode

            if !isConverted, source.isSupportsDirectPlay != true, source.isSupportsDirectStream != true {
                hasPlayablePath = false
            }
        } else {
            transcodeReasons = estimatedTranscodeReasons(
                source: source,
                video: video,
                audio: audio,
                subtitle: subtitle,
                input: input
            )
            isConverted = transcodeReasons.isNotEmpty
            isBurningSubtitles = transcodeReasons.contains(.subtitleCodecNotSupported) && subtitle?.isTextSubtitleStream == false
        }

        var reasons: [PlaybackHealthReason] = []

        if !hasPlayablePath {
            reasons.append(.noPlayablePath)
        }

        if transcodeReasons.contains(.videoRangeTypeNotSupported) {
            if video?.videoRangeType?.isDolbyVision == true {
                reasons.append(.dolbyVision(profile: video?.dvProfile))
            } else {
                reasons.append(.hdrConversion)
            }
        }

        if transcodeReasons.isDisjoint(with: videoFormatReasons) == false {
            reasons.append(.videoFormat(videoFormatLabel(video)))
        }

        if transcodeReasons.contains(.videoResolutionNotSupported) {
            reasons.append(.videoResolution)
        }

        if isBurningSubtitles {
            reasons.append(.imageSubtitles(subtitle?.codec?.uppercased() ?? ""))
        }

        if transcodeReasons.isDisjoint(with: bitrateReasons) == false {
            let sourceMbps = megabits(source.bitrate ?? video?.bitRate ?? 0)
            reasons.append(.bitrateLimit(sourceMbps: sourceMbps, limitMbps: input.maxBitrate.map(megabits)))
        }

        if transcodeReasons.isDisjoint(with: audioReasons) == false {
            reasons.append(.audioFormat(audio?.codec?.uppercased() ?? ""))
        }

        if transcodeReasons.isDisjoint(with: containerReasons) == false {
            reasons.append(.container(source.container?.uppercased() ?? ""))
        }

        if transcodeReasons.contains(.subtitleCodecNotSupported), !isBurningSubtitles {
            reasons.append(.subtitleConversion)
        }

        if isConverted, reasons.isEmpty {
            reasons.append(.unknownConversion)
        }

        let reencodesVideo = reasons.contains(where: \.isVideoReencode)
            || (reasons.contains(.unknownConversion) && source.isSupportsDirectStream != true)

        let tier: PlaybackHealthTier = {
            if !hasPlayablePath {
                return .poor
            }

            if reencodesVideo {
                let isLarge = (video?.height ?? 0) > heavyHeightLimit
                let isToneMapping = reasons.contains(.hdrConversion) || reasons.contains { reason in
                    if case .dolbyVision = reason { return true }
                    return false
                }

                return isLarge || isToneMapping ? .poor : .heavy
            }

            return isConverted ? .light : .direct
        }()

        if !reencodesVideo, let bitrate = source.bitrate, bitrate >= highBitrateWarning {
            reasons.append(.highBitrate(mbps: megabits(bitrate)))
        }

        var verdict = PlaybackHealthVerdict(tier: tier, reasons: reasons, target: nil, stalledBefore: input.stalledBefore)

        if verdict.isBadgeWorthy {
            verdict.target = target(
                for: reasons,
                video: video,
                device: input.device,
                maxBitrate: input.maxBitrate,
                hasStalled: input.stalledBefore >= stallsWorthReporting
            )
        }

        return verdict
    }

    // MARK: - Target

    /// A copy that would play directly here: keeps 4K and HDR when the device handles them.
    static func target(
        for reasons: [PlaybackHealthReason],
        video: MediaStream?,
        device: PlaybackHealthDevice,
        maxBitrate: Int?,
        hasStalled: Bool
    ) -> PlaybackHealthTarget {
        let sourceHeight = video?.height ?? 1080
        let sourceIsHDR = video?.videoRangeType?.isHDR == true

        var bitrateLimit: Int?
        var shrinks = reasons.contains(.videoResolution)

        for reason in reasons {
            switch reason {
            case let .bitrateLimit(_, limitMbps):
                bitrateLimit = limitMbps
                shrinks = true

            case .highBitrate:
                if hasStalled {
                    bitrateLimit = 20
                }

            default: ()
            }
        }

        let keeps4K = sourceHeight > heavyHeightLimit && device.supportsHEVC && !shrinks
        let height = keeps4K ? 2160 : min(sourceHeight, 1080)

        return PlaybackHealthTarget(
            height: height,
            isHEVC: device.supportsHEVC,
            isHDR: sourceIsHDR && device.supportsHDR && !reasons.contains(.hdrConversion),
            convertsAudio: reasons.contains { reason in
                if case .audioFormat = reason { return true }
                return false
            },
            usesTextSubtitles: reasons.contains { reason in
                if case .imageSubtitles = reason { return true }
                return false
            },
            maxMbps: bitrateLimit ?? (keeps4K ? nil : (maxBitrate.map(megabits)))
        )
    }

    // MARK: - Heuristics

    /// What the server would likely say, from the file's facts and the device profile.
    /// Used when the PlaybackInfo request isn't available.
    static func estimatedTranscodeReasons(
        source: MediaSourceInfo,
        video: MediaStream?,
        audio: MediaStream?,
        subtitle: MediaStream?,
        input: PlaybackHealthInput
    ) -> Set<TranscodeReason> {
        var reasons: Set<TranscodeReason> = []
        let profiles = input.deviceProfile.directPlayProfiles ?? []

        if let video {
            let playsInContainer = input.deviceProfile.canPlay(type: .video, videoCodec: video.codec, container: source.container)

            if !playsInContainer {
                let playsSomewhere = profiles.contains { $0.type == .video && csv($0.videoCodec, contains: video.codec) }
                reasons.insert(playsSomewhere ? .containerNotSupported : .videoCodecNotSupported)
            }

            if let range = video.videoRangeType {
                if range.isHDR, !input.device.supportsHDR {
                    reasons.insert(.videoRangeTypeNotSupported)
                } else if range == .dovi || range == .doviWithEL || range == .doviWithELHDR10Plus, !input.device.supportsDolbyVision {
                    reasons.insert(.videoRangeTypeNotSupported)
                }
            }
        }

        if let audio, !input.deviceProfile.canPlay(type: .video, audioCodec: audio.codec, container: source.container) {
            reasons.insert(.audioCodecNotSupported)
        }

        if let maxBitrate = input.maxBitrate, let bitrate = source.bitrate, bitrate > maxBitrate {
            reasons.insert(.containerBitrateExceedsLimit)
        }

        if let subtitle, subtitle.isTextSubtitleStream == false {
            let profile = input.deviceProfile
            let canShow = profile.canPlay(subtitleFormat: subtitle.codec, method: .embed)
                || profile.canPlay(subtitleFormat: subtitle.codec, method: .external)
                || profile.canPlay(subtitleFormat: subtitle.codec, method: .hls)

            if !canShow {
                reasons.insert(.subtitleCodecNotSupported)
            }
        }

        return reasons
    }

    // MARK: - Helpers

    /// The `TranscodeReasons` query parameter of a transcoding URL.
    static func transcodeReasons(in transcodingURL: String?) -> Set<TranscodeReason> {
        guard let transcodingURL, let components = URLComponents(string: transcodingURL) else { return [] }

        let value = components.queryItems?
            .first { $0.name.lowercased() == "transcodereasons" }?
            .value ?? ""

        return Set(
            value
                .split(separator: ",")
                .compactMap { TranscodeReason(rawValue: $0.trimmingCharacters(in: .whitespaces)) }
        )
    }

    static func megabits(_ bitrate: Int) -> Int {
        Int((Double(bitrate) / 1_000_000).rounded())
    }

    private static func selectedStream(of type: MediaStreamType, index: Int?, in streams: [MediaStream]) -> MediaStream? {
        if let index {
            guard index >= 0 else { return nil }

            return streams.first { $0.type == type && $0.index == index }
        }

        // Subtitles stay off unless one is selected or marked default.
        guard type == .audio else { return nil }

        return streams.first { $0.type == type }
    }

    private static func videoFormatLabel(_ video: MediaStream?) -> String {
        guard let codec = video?.codec?.uppercased() else { return "" }

        if let bitDepth = video?.bitDepth, bitDepth > 8 {
            return "\(codec) \(bitDepth)-bit"
        }

        return codec
    }

    private static func csv(_ list: String?, contains candidate: String?) -> Bool {
        guard let list else { return true }
        guard let candidate = candidate?.lowercased() else { return false }

        return list
            .lowercased()
            .split(separator: ",")
            .contains { $0.trimmingCharacters(in: .whitespaces) == candidate }
    }
}
