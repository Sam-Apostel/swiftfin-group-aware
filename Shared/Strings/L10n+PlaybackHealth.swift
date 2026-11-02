//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// English strings for playback health: the pre-play verdict, stutter detection and the lighter copy list.
extension L10n {

    enum PlaybackHealth {

        // MARK: - Verdict

        static let title = "Playback"
        static let whyTitle = "Why"
        static let fixTitle = "What would fix it"
        static let details = "Details"
        static let badgeHeavy = "May stutter"
        static let badgeLikely = "Likely to stutter"
        static let badgeSlow = "Will stutter"
        static let badgePoor = "Won't play well"
        static let badgeStalled = "Stuttered before"
        static let serverFixTitle = "On your server"

        static func badgeTitle(_ verdict: PlaybackHealthVerdict) -> String {
            switch (verdict.tier, verdict.server) {
            case (.poor, .tooSlow):
                badgeSlow
            case (.poor, .some):
                badgeLikely
            case (.poor, .none):
                badgePoor
            case (.heavy, _):
                badgeHeavy
            case (.direct, _), (.light, _):
                badgeStalled
            }
        }

        static func tierTitle(_ tier: PlaybackHealthTier) -> String {
            switch tier {
            case .direct:
                "Plays directly"
            case .light:
                "Light: your server only converts the audio or container"
            case .heavy:
                "Heavy: your server re-encodes the video"
            case .poor:
                "Won't play here"
            }
        }

        static func tierDescription(_ tier: PlaybackHealthTier) -> String {
            switch tier {
            case .direct:
                "The file is sent as is. Nothing for your server to do."
            case .light:
                "Cheap for your server. This should play smoothly."
            case .heavy:
                "Converting video takes a lot of work. A server that falls behind pauses to catch up."
            case .poor:
                "Your server can't play or convert this file for this device."
            }
        }

        /// The headline of the details sheet: the server outlook when the video is re-encoded, else the tier.
        static func verdictTitle(_ verdict: PlaybackHealthVerdict) -> String {
            guard let server = verdict.server else { return tierTitle(verdict.tier) }

            switch server {
            case .smooth:
                return "Plays smoothly: your server converts it fast enough"

            case .hardwareReady:
                return "Should play smoothly: not tested yet"

            case .tight:
                return "May stutter: your server only just keeps up"

            case .tooSlow:
                return "Will stutter: your server converts it too slowly"

            case .softwareFallback, .softwareOnly:
                let outcome = verdict.tier == .poor ? "Likely to stutter" : "May stutter"
                return "\(outcome): your server's processor does the work"

            case .notMeasured:
                return "May stutter: not measured on your server yet"
            }
        }

        /// The verdict in a sentence: the server outlook when the video is re-encoded, else the tier.
        static func verdictDescription(_ verdict: PlaybackHealthVerdict) -> String {
            guard let server = verdict.server, let streamClass = verdict.streamClass else { return tierDescription(verdict.tier) }

            return serverDescription(server, streamClass: streamClass)
        }

        /// "4K HDR" when tone mapping, else e.g. "4K HEVC" or "HD H.264".
        static func streamClassLabel(_ streamClass: TranscodeStreamClass) -> String {
            let resolution = streamClass.is4K ? "4K" : "HD"

            return streamClass.toneMaps ? "\(resolution) HDR" : "\(resolution) \(codecName(streamClass.codec))"
        }

        static func codecName(_ codec: String) -> String {
            switch codec {
            case "hevc":
                "HEVC"
            case "h264":
                "H.264"
            case "unknown":
                "video"
            default:
                codec.uppercased()
            }
        }

        static func hardwareName(_ hardware: String) -> String {
            switch hardware {
            case "qsv":
                "Intel Quick Sync"
            case "vaapi":
                "VA-API"
            case "nvenc":
                "NVIDIA NVENC"
            case "amf":
                "AMD AMF"
            case "videotoolbox":
                "Apple VideoToolbox"
            case "rkmpp":
                "Rockchip MPP"
            case "v4l2m2m":
                "V4L2"
            default:
                hardware.uppercased()
            }
        }

        static func serverDescription(_ server: PlaybackHealthServerOutlook, streamClass: TranscodeStreamClass) -> String {
            let label = streamClassLabel(streamClass)
            let isDemanding = streamClass.is4K || streamClass.toneMaps

            switch server {
            case let .smooth(fps, neededFPS):
                return "Your server converts \(label) at \(fps) fps — this video needs \(neededFPS). Plays smoothly."

            case let .tight(fps, neededFPS):
                return "Your server converts \(label) at \(fps) fps, barely the \(neededFPS) this video needs. It may pause to catch up."

            case let .tooSlow(fps, neededFPS):
                return "Your server converts \(label) at \(fps) fps, but this video needs \(neededFPS). It will stutter."

            case let .hardwareReady(hardware):
                let toneMapping = streamClass.toneMaps ? ", tone mapping included" : ""
                return "Your server converts \(label) with \(hardwareName(hardware))\(toneMapping). "
                    + "Should be fine, not tested yet: Couchfin measures the speed the first time you play one."

            case let .softwareFallback(hardware, gap):
                let outcome = isDemanding ? "\(label) is likely to stutter." : "It may stutter."

                switch gap {
                case let .decoding(format):
                    return "Your server's \(hardwareName(hardware)) isn't set up to decode \(format), so its processor does it. \(outcome)"
                case .toneMapping:
                    return "Your server's \(hardwareName(hardware)) isn't set up to tone map HDR, so its processor does it. \(outcome)"
                case .encoding:
                    return "Hardware encoding is off on your server, so its processor encodes the video. \(outcome)"
                }

            case .softwareOnly:
                let outcome = isDemanding ? "\(label) is likely to stutter." : "It may stutter."
                return "Your server has no hardware acceleration set up, so its processor converts everything. \(outcome)"

            case .notMeasured:
                return "Couchfin hasn't seen your server convert \(label) yet. It measures the speed the first time you play one, "
                    + "and learns the server's setup when an administrator opens Couchfin."
            }
        }

        /// What an administrator can change on the server, when it would help.
        static func serverFix(_ server: PlaybackHealthServerOutlook?) -> String? {
            let place = "In the Jellyfin dashboard, Playback › Transcoding"

            switch server {
            case let .softwareFallback(_, .decoding(format)):
                return "\(place): turn on hardware decoding for \(format), if your hardware supports it."
            case .softwareFallback(_, .toneMapping):
                return "\(place): turn on tone mapping."
            case .softwareFallback(_, .encoding):
                return "\(place): turn on hardware encoding."
            case .softwareOnly:
                return "\(place): choose your server's hardware acceleration, e.g. Intel Quick Sync or VA-API on an Intel-based server."
            case .hardwareReady, .notMeasured, .smooth, .tight, .tooSlow, .none:
                return nil
            }
        }

        static func reason(_ reason: PlaybackHealthReason) -> String {
            switch reason {
            case let .dolbyVision(profile):
                if let profile {
                    "Dolby Vision profile \(profile) isn't supported here"
                } else {
                    "This Dolby Vision video isn't supported here"
                }

            case .hdrConversion:
                "This HDR video has to be converted for your screen"

            case let .videoFormat(format):
                format.isEmpty ? "The video format has to be converted" : "The video format (\(format)) has to be converted"

            case .videoResolution:
                "The video is bigger than your resolution setting"

            case let .imageSubtitles(format):
                format.isEmpty ? "Image subtitles must be burned in" : "Image subtitles (\(format)) must be burned in"

            case let .bitrateLimit(sourceMbps, limitMbps):
                if let limitMbps {
                    "The video is \(sourceMbps) Mbps, more than your \(limitMbps) Mbps quality setting"
                } else {
                    "The video is \(sourceMbps) Mbps, more than your quality setting allows"
                }

            case let .audioFormat(format):
                format.isEmpty ? "The audio is converted" : "The audio (\(format)) is converted"

            case let .container(format):
                format.isEmpty ? "The file is repackaged for streaming" : "The file (\(format)) is repackaged for streaming"

            case .subtitleConversion:
                "The subtitles are converted"

            case .unknownConversion:
                "Your server converts this one for this device"

            case let .highBitrate(mbps):
                "\(mbps) Mbps peaks may be too much for Wi-Fi"

            case .noPlayablePath:
                "Your server can't play or convert this file for this device"
            }
        }

        static func targetDescription(_ target: PlaybackHealthTarget) -> String {
            let resolution = target.height >= 2000 ? "4K" : "\(target.height)p"
            let codec = target.isHEVC ? "HEVC" : "H.264"
            let range = target.isHDR ? "HDR10" : "SDR"

            var description = "A \(resolution) \(codec) \(range) copy"

            if let maxMbps = target.maxMbps {
                description += " under \(maxMbps) Mbps"
            }

            switch (target.convertsAudio, target.usesTextSubtitles) {
            case (true, true):
                description += " with AAC or AC3 audio and text subtitles"
            case (true, false):
                description += " with AAC or AC3 audio"
            case (false, true):
                description += " with text subtitles"
            case (false, false): ()
            }

            return description + " would play directly."
        }

        // MARK: - Stutters

        static func stutterNote(count: Int, diagnosis: PlaybackHealthDiagnosis?) -> String {
            let start = count == 1 ? "That stuttered once" : "That stuttered \(count) times"

            switch diagnosis {
            case .serverTooSlow:
                return "\(start) — your server couldn't convert it fast enough. "
                    + "Couchfin will remember, and this one should be pre-encoded."

            case .network:
                return "\(start) — the network couldn't keep up with this file. "
                    + "Couchfin will remember and read further ahead next time."

            case .unknown, .none:
                return "\(start). Couchfin will remember and read further ahead next time."
            }
        }

        static func diagnosisTitle(_ diagnosis: PlaybackHealthDiagnosis) -> String {
            switch diagnosis {
            case .serverTooSlow:
                "Your server can't convert this fast enough"
            case .network:
                "The network can't keep up with this file's bitrate"
            case .unknown:
                "Still working out why"
            }
        }

        /// The reason saved in the lighter copy list.
        static func diagnosisDescription(_ diagnosis: PlaybackHealthDiagnosis, reasons: [PlaybackHealthReason]) -> String {
            let details = reasons.map(reason).joined(separator: "; ")

            return details.isEmpty ? diagnosisTitle(diagnosis) : "\(diagnosisTitle(diagnosis)) (\(details))"
        }

        static func stalledBefore(_ count: Int) -> String {
            "Stuttered \(count) times last time on this device"
        }

        // MARK: - Info overlay

        static let health = "Playback health"
        static let stalls = "Stutters"
        static let diagnosis = "Likely cause"
        static let steadyPlayback = "Steady playback"
        static let on = "On"
        static let off = "Off"
        static let serverSpeed = "Server speed"

        static func framerate(_ framerate: Double, needed: Double?) -> String {
            if let needed {
                "\(Int(framerate.rounded())) fps (needs \(Int(needed.rounded())))"
            } else {
                "\(Int(framerate.rounded())) fps"
            }
        }

        // MARK: - Settings

        static let steadyPlaybackFooter =
            "When something stutters, Couchfin remembers and reads further ahead the next time you play it on this device."

        // MARK: - Lighter copies

        static let lighterCopies = "Needs a lighter copy"
        static let lighterCopiesDescription =
            "Videos that stuttered because your server couldn't convert them fast enough or the network couldn't keep up. "
                + "A copy made for streaming will play smoothly."
        static let noLighterCopies = "Nothing stuttered. Everything plays smoothly."
        static let copyList = "Copy list"
        static let markDone = "Done"

        static func reportedBy(_ name: String, device: String, date: String) -> String {
            "\(name) on \(device), \(date)"
        }

        static func stallsTotal(_ count: Int) -> String {
            count == 1 ? "Stuttered once" : "Stuttered \(count) times"
        }

        static func listLine(name: String, reason: String, target: String) -> String {
            target.isEmpty ? "\(name)\n  Why: \(reason)" : "\(name)\n  Why: \(reason)\n  Make: \(target)"
        }
    }
}
