//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

// MARK: - Encoding configuration

/// `GET /System/Configuration/encoding`, decoded leniently: every field is optional and a field
/// with an unexpected type is skipped instead of failing the whole response.
struct EncodingConfigurationDTO: Decodable {

    var hardwareAccelerationType: String?
    var enableHardwareEncoding: Bool?
    var hardwareDecodingCodecs: [String]?
    var enableDecodingColorDepth10Hevc: Bool?
    var enableDecodingColorDepth10Vp9: Bool?
    var enableTonemapping: Bool?
    var enableVppTonemapping: Bool?
    var enableVideoToolboxTonemapping: Bool?
    var allowHevcEncoding: Bool?

    private enum CodingKeys: String, CodingKey {
        case hardwareAccelerationType = "HardwareAccelerationType"
        case enableHardwareEncoding = "EnableHardwareEncoding"
        case hardwareDecodingCodecs = "HardwareDecodingCodecs"
        case enableDecodingColorDepth10Hevc = "EnableDecodingColorDepth10Hevc"
        case enableDecodingColorDepth10Vp9 = "EnableDecodingColorDepth10Vp9"
        case enableTonemapping = "EnableTonemapping"
        case enableVppTonemapping = "EnableVppTonemapping"
        case enableVideoToolboxTonemapping = "EnableVideoToolboxTonemapping"
        case allowHevcEncoding = "AllowHevcEncoding"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.hardwareAccelerationType = try? container.decodeIfPresent(String.self, forKey: .hardwareAccelerationType)
        self.enableHardwareEncoding = try? container.decodeIfPresent(Bool.self, forKey: .enableHardwareEncoding)
        self.hardwareDecodingCodecs = try? container.decodeIfPresent([String].self, forKey: .hardwareDecodingCodecs)
        self.enableDecodingColorDepth10Hevc = try? container.decodeIfPresent(Bool.self, forKey: .enableDecodingColorDepth10Hevc)
        self.enableDecodingColorDepth10Vp9 = try? container.decodeIfPresent(Bool.self, forKey: .enableDecodingColorDepth10Vp9)
        self.enableTonemapping = try? container.decodeIfPresent(Bool.self, forKey: .enableTonemapping)
        self.enableVppTonemapping = try? container.decodeIfPresent(Bool.self, forKey: .enableVppTonemapping)
        self.enableVideoToolboxTonemapping = try? container.decodeIfPresent(Bool.self, forKey: .enableVideoToolboxTonemapping)
        self.allowHevcEncoding = try? container.decodeIfPresent(Bool.self, forKey: .allowHevcEncoding)
    }
}

// MARK: - Encoding facts

/// How the server is set up to convert video, read by an administrator and shared with everyone.
struct ServerEncodingFacts: Codable, Equatable {

    /// Jellyfin's `HardwareAccelerationType`: none, qsv, vaapi, nvenc, amf, videotoolbox, rkmpp or v4l2m2m.
    var hardwareAcceleration: String
    var hardwareEncoding: Bool
    /// Codecs the graphics hardware decodes, lowercased.
    var hardwareDecodingCodecs: [String]
    var decodesHEVC10Bit: Bool
    var decodesVP910Bit: Bool
    /// OpenCL or CUDA tone mapping.
    var toneMapping: Bool
    /// Intel VPP tone mapping.
    var vppToneMapping: Bool
    /// Apple VideoToolbox tone mapping.
    var videoToolboxToneMapping: Bool
    var allowsHEVCEncoding: Bool
    var serverName: String?
    var version: String?
    var operatingSystem: String?
    var architecture: String?
    var updatedAt: Date

    var hasHardware: Bool {
        hardwareAcceleration != "none"
    }

    var hasHardwareToneMapping: Bool {
        hasHardware && (toneMapping || vppToneMapping || videoToolboxToneMapping)
    }

    /// Whether the graphics hardware decodes this codec at this bit depth.
    func decodesInHardware(codec: String, bitDepth: Int?) -> Bool {
        let codec = TranscodeStreamClass.normalizedCodec(codec)

        guard hasHardware, hardwareDecodingCodecs.contains(codec) else { return false }
        guard let bitDepth, bitDepth > 8 else { return true }

        switch codec {
        case "hevc":
            return decodesHEVC10Bit
        case "vp9":
            return decodesVP910Bit
        default:
            return true
        }
    }
}

extension ServerEncodingFacts {

    init(configuration: EncodingConfigurationDTO, systemInfo: SystemInfo?, now: Date) {
        let hardware = (configuration.hardwareAccelerationType ?? "").lowercased()

        self.init(
            hardwareAcceleration: hardware.isEmpty ? "none" : hardware,
            hardwareEncoding: configuration.enableHardwareEncoding ?? true,
            hardwareDecodingCodecs: (configuration.hardwareDecodingCodecs ?? []).map(TranscodeStreamClass.normalizedCodec),
            decodesHEVC10Bit: configuration.enableDecodingColorDepth10Hevc ?? false,
            decodesVP910Bit: configuration.enableDecodingColorDepth10Vp9 ?? false,
            toneMapping: configuration.enableTonemapping ?? false,
            vppToneMapping: configuration.enableVppTonemapping ?? false,
            videoToolboxToneMapping: configuration.enableVideoToolboxTonemapping ?? false,
            allowsHEVCEncoding: configuration.allowHevcEncoding ?? false,
            serverName: systemInfo?.serverName,
            version: systemInfo?.version,
            operatingSystem: systemInfo?.operatingSystemDisplayName ?? systemInfo?.operatingSystem,
            architecture: systemInfo?.systemArchitecture,
            updatedAt: now
        )
    }
}

// MARK: - Stream class

/// The kind of conversion a measurement applies to: what the server decodes, how big, whether it tone maps,
/// and with which hardware.
struct TranscodeStreamClass: Codable, Hashable {

    /// The source video codec, normalized (hevc, h264, av1, vp9, ...).
    var codec: String
    var is4K: Bool
    /// HDR or Dolby Vision mapped to SDR.
    var toneMaps: Bool
    /// The hardware the server used, `none` for the processor.
    var hardware: String

    var key: String {
        [codec, is4K ? "2160" : "1080", toneMaps ? "tm" : "sdr", hardware].joined(separator: ".")
    }

    static func normalizedCodec(_ codec: String?) -> String {
        let codec = (codec ?? "").lowercased()

        switch codec {
        case "h265", "hevc":
            return "hevc"
        case "avc", "h264":
            return "h264"
        case "":
            return "unknown"
        default:
            return codec
        }
    }

    /// 4K: at least 3800 pixels wide, or taller than 1440 lines.
    static func isFourK(width: Int?, height: Int?) -> Bool {
        (width ?? 0) >= 3800 || (height ?? 0) > PlaybackHealthClassifier.heavyHeightLimit
    }

    /// The class of converting `video`. HDR is tone mapped when the device can't take its range,
    /// or when the output codec can't carry HDR (`outputCodec` is `nil` before playback).
    static func make(
        video: MediaStream?,
        transcodeReasons: Set<TranscodeReason>,
        outputCodec: String?,
        hardware: String
    ) -> TranscodeStreamClass {
        let isHDR = video?.videoRangeType?.isHDR == true
        let output = outputCodec.map(normalizedCodec)
        let outputKeepsHDR = output == nil || output == "hevc" || output == "av1"

        return TranscodeStreamClass(
            codec: normalizedCodec(video?.codec),
            is4K: isFourK(width: video?.width, height: video?.height),
            toneMaps: isHDR && (transcodeReasons.contains(.videoRangeTypeNotSupported) || !outputKeepsHDR),
            hardware: hardware
        )
    }
}

// MARK: - Speed summary

/// How fast the server converted one class of video, as a rolling summary of playback sessions.
struct TranscodeSpeedSummary: Codable, Equatable {

    /// Sessions kept for the median.
    static let maxSessions = 9

    var streamClass: TranscodeStreamClass
    var bestFPS: Double
    /// Each session's typical speed, oldest first.
    var sessionFPS: [Double]
    /// Readings across all sessions.
    var sampleCount: Int
    var lastSeen: Date

    var medianFPS: Double {
        TranscodeSpeedMeter.median(sessionFPS) ?? bestFPS
    }

    init(streamClass: TranscodeStreamClass, fps: Double, samples: Int, at date: Date) {
        self.streamClass = streamClass
        self.bestFPS = fps
        self.sessionFPS = [fps]
        self.sampleCount = samples
        self.lastSeen = date
    }

    func recording(fps: Double, samples: Int, at date: Date) -> TranscodeSpeedSummary {
        var summary = self
        summary.bestFPS = max(bestFPS, fps)
        summary.sessionFPS = Array((sessionFPS + [fps]).suffix(Self.maxSessions))
        summary.sampleCount += samples
        summary.lastSeen = max(lastSeen, date)
        return summary
    }
}

// MARK: - Speed meter

/// Turns the server's transcoding progress readings into one speed per session.
enum TranscodeSpeedMeter {

    /// Jellyfin throttles a conversion that is far ahead (180 seconds by default), which lowers its framerate.
    /// Readings this far ahead or more are left out: they show throttling, not the server's speed.
    static let throttleFreeLeadSeconds: Double = 150
    /// Fewer readings than this don't make a measurement.
    static let minimumSamples = 2

    /// Whether a reading shows the server converting video at full speed.
    static func isMeasurement(_ sample: PlaybackHealthTranscodeSample) -> Bool {
        guard sample.isVideoDirect != true, let framerate = sample.framerate, framerate > 0 else { return false }

        if let lead = sample.leadSeconds, lead >= throttleFreeLeadSeconds {
            return false
        }

        return true
    }

    /// The session's speed: the median of its full-speed readings.
    static func sessionFPS(_ framerates: [Double]) -> Double? {
        guard framerates.count >= minimumSamples else { return nil }

        return median(framerates)
    }

    static func median(_ values: [Double]) -> Double? {
        guard values.isNotEmpty else { return nil }

        let sorted = values.sorted()
        let middle = sorted.count / 2

        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }

        return sorted[middle]
    }
}

// MARK: - Facts

/// Everything known about the server's ability to convert video: its setup and what was measured.
struct ServerPlaybackFacts: Codable, Equatable {

    var encoding: ServerEncodingFacts?
    /// Speed summaries by `TranscodeStreamClass.key`.
    var speeds: [String: TranscodeSpeedSummary]

    static let empty = ServerPlaybackFacts(encoding: nil, speeds: [:])

    /// The measurement for converting this class of video. When the setup is known, only measurements
    /// with the current hardware count; otherwise the most recent one.
    func speed(for streamClass: TranscodeStreamClass) -> TranscodeSpeedSummary? {
        let candidates = speeds.values.filter { summary in
            summary.streamClass.codec == streamClass.codec
                && summary.streamClass.is4K == streamClass.is4K
                && summary.streamClass.toneMaps == streamClass.toneMaps
        }

        if let hardware = encoding?.hardwareAcceleration {
            return candidates
                .filter { $0.streamClass.hardware == hardware }
                .max { $0.lastSeen < $1.lastSeen }
        }

        return candidates.max { $0.lastSeen < $1.lastSeen }
    }

    func recording(fps: Double, samples: Int, streamClass: TranscodeStreamClass, at date: Date) -> ServerPlaybackFacts {
        var facts = self
        let key = streamClass.key

        if let existing = speeds[key] {
            facts.speeds[key] = existing.recording(fps: fps, samples: samples, at: date)
        } else {
            facts.speeds[key] = TranscodeSpeedSummary(streamClass: streamClass, fps: fps, samples: samples, at: date)
        }

        return facts
    }
}

// MARK: - Storage

/// Storage format of the server facts: the Jellyfin DisplayPreferences `playback-health-server`
/// (client `couchfin`, next to the lighter copy list), one custom pref for the setup and one per measured class.
///
/// Every user keeps a copy. An administrator reads all copies, merges them and writes the result back to everyone,
/// so users who can't read the encoding configuration still get it.
enum ServerPlaybackFactsSync {

    static let displayPreferencesID = "playback-health-server"
    static let encodingKey = "srv.encoding"
    static let speedKeyPrefix = "srv.speed."
    /// The most measurements kept, most recent first.
    static let maxSpeeds = 40

    static func facts(in customPrefs: [String: String?]) -> ServerPlaybackFacts {
        let decoder = AudienceWatchlistSync.makeDecoder()
        var facts = ServerPlaybackFacts.empty

        for (key, value) in customPrefs {
            guard let data = value?.data(using: .utf8) else { continue }

            if key == encodingKey {
                facts.encoding = try? decoder.decode(ServerEncodingFacts.self, from: data)
            } else if key.hasPrefix(speedKeyPrefix), let summary = try? decoder.decode(TranscodeSpeedSummary.self, from: data) {
                facts.speeds[summary.streamClass.key] = summary
            }
        }

        return facts
    }

    /// Merges copies: the newest setup wins; per class the most recent summary wins, keeping the best speed of all.
    static func merge(_ copies: [ServerPlaybackFacts]) -> ServerPlaybackFacts {
        var merged = ServerPlaybackFacts.empty

        for copy in copies {
            if let encoding = copy.encoding, encoding.updatedAt > (merged.encoding?.updatedAt ?? .distantPast) {
                merged.encoding = encoding
            }

            for (key, summary) in copy.speeds {
                guard let existing = merged.speeds[key] else {
                    merged.speeds[key] = summary
                    continue
                }

                var newest = summary.lastSeen > existing.lastSeen ? summary : existing
                newest.bestFPS = max(summary.bestFPS, existing.bestFPS)
                merged.speeds[key] = newest
            }
        }

        return merged
    }

    /// The custom prefs to POST for `facts`, capped to `maxSpeeds`.
    static func customPrefs(for facts: ServerPlaybackFacts) -> [String: String] {
        let encoder = AudienceWatchlistSync.makeEncoder()
        var result: [String: String] = [:]

        if let encoding = facts.encoding, let data = try? encoder.encode(encoding) {
            result[encodingKey] = String(data: data, encoding: .utf8)
        }

        let kept = facts.speeds.values
            .sorted { $0.lastSeen > $1.lastSeen }
            .prefix(maxSpeeds)

        for summary in kept {
            if let data = try? encoder.encode(summary) {
                result[speedKeyPrefix + summary.streamClass.key] = String(data: data, encoding: .utf8)
            }
        }

        return result
    }

    /// Whether a stored copy differs from `facts`.
    static func needsWrite(stored: [String: String?], facts: ServerPlaybackFacts) -> Bool {
        let wanted = customPrefs(for: facts)
        var current: [String: String] = [:]

        for (key, value) in stored where key == encodingKey || key.hasPrefix(speedKeyPrefix) {
            if let value {
                current[key] = value
            }
        }

        return current != wanted
    }
}
