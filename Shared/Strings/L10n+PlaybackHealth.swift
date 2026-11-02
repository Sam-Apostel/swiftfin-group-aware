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
        static let badgePoor = "Won't play well"
        static let badgeStalled = "Stuttered before"

        static func tierTitle(_ tier: PlaybackHealthTier) -> String {
            switch tier {
            case .direct:
                "Plays directly"
            case .light:
                "Light: your server only converts the audio or container"
            case .heavy:
                "Heavy: your server re-encodes the video, which may stutter"
            case .poor:
                "Won't play well here"
            }
        }

        static func tierDescription(_ tier: PlaybackHealthTier) -> String {
            switch tier {
            case .direct:
                "The file is sent as is. Nothing for your server to do."
            case .light:
                "Cheap for your server. This should play smoothly."
            case .heavy:
                "Converting video takes a lot of work. A small server can fall behind and pause to catch up."
            case .poor:
                "Your server would have to convert a very big or HDR video, or can't play it at all."
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
