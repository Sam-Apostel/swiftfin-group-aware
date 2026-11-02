//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// English strings for "What it takes to watch 4K on this TV".
extension L10n {

    enum FourKReadiness {

        // MARK: - Screen

        static let title = "Watch 4K on this TV"
        static let entryTitle = "What it takes to watch 4K on this TV"
        static let checking = "Checking your TV, network, player and library…"
        static let checkAgain = "Check again"
        static let overallReady = "Ready for 4K HDR"
        static let badge = "4K"

        static func overallFixes(_ count: Int) -> String {
            count == 1 ? "1 thing to fix" : "\(count) things to fix"
        }

        static func scanLimited(scanned: Int, total: Int) -> String {
            "Looked at the first \(scanned) of \(total) 4K videos."
        }

        // MARK: - Setting

        static let nativePlayerForHDR = "Use the native player for HDR and Dolby Vision"
        static let nativePlayerForHDRFooter =
            "VLC and mpv show HDR videos in SDR on Apple TV. With this on, HDR and Dolby Vision videos open in the native player "
                + "when your TV shows HDR. Everything else keeps your chosen player."

        // MARK: - Display

        static let resolutionTitle = "4K picture"
        static let resolutionFix =
            "Use an HDMI port on the TV that supports 4K HDR (often only HDMI 1 or 2), with a Premium High Speed "
                + "or Ultra High Speed HDMI cable, and turn on \"enhanced HDMI\" for that port in the TV's settings "
                + "(also called HDMI UHD Color, Input Signal Plus or HDMI Deep Colour). "
                + "Then pick a 4K format in Settings › Video and Audio › Format."

        static func resolutionDetail(width: Int, height: Int) -> String {
            if width >= 3800 {
                "Your TV gets 4K (\(width)×\(height))."
            } else {
                "The Apple TV only sends \(width)×\(height) to your TV."
            }
        }

        static let hdrTitle = "HDR"
        static let hdrFix =
            "Turn on \"enhanced HDMI\" for this HDMI port on the TV, then in Settings › Video and Audio › Format choose 4K SDR "
                + "and turn on Match Content › Dynamic Range (or choose 4K HDR or 4K Dolby Vision)."

        static func hdrDetail(_ display: FourKDisplayFacts) -> String {
            guard display.isEligibleForHDR else { return "Your TV doesn't report HDR to the Apple TV." }

            switch (display.supportsHDR10, display.supportsDolbyVision) {
            case (_, true):
                return "Your TV shows HDR10 and Dolby Vision."
            case (true, false):
                return "Your TV shows HDR10. No Dolby Vision: those videos play in HDR10 when they include it."
            case (false, false):
                return "Your TV shows HDR."
            }
        }

        static let matchContentTitle = "Match Content"
        static let matchContentFix = "Settings › Video and Audio › Match Content → turn on Dynamic Range and Frame Rate."

        static func matchContentDetail(_ isEnabled: Bool?) -> String {
            switch isEnabled {
            case .some(true):
                "On: the TV switches to HDR and to the film's frame rate when a video starts."
            case .some(false):
                "Off: HDR videos are squeezed into the menu's picture mode, and films judder at 60 Hz."
            case .none:
                "Couldn't read the Match Content setting."
            }
        }

        // MARK: - Network

        static let networkTitle = "Network to your server"
        static let networkOfflineFix = "Connect the Apple TV to your home network."

        static func linkName(_ link: FourKNetworkFacts.Link) -> String {
            switch link {
            case .wired:
                "Wired (Ethernet)"
            case .wifi:
                "Wi-Fi"
            case .other:
                "Connected"
            case .offline:
                "Not connected"
            }
        }

        static func networkUnmeasured(_ link: FourKNetworkFacts.Link) -> String {
            link == .offline ? "The Apple TV isn't connected." : "\(linkName(link)). Couldn't measure the speed to your server."
        }

        static func networkDetail(link: FourKNetworkFacts.Link, measuredMbps: Int, neededMbps: Int, hasLibraryFigure: Bool) -> String {
            let need = hasLibraryFigure
                ? "your biggest 4K file needs about \(neededMbps) Mbps with its peaks"
                : "4K WEB-DL needs 15–40 Mbps, 4K remuxes 50–100 Mbps with peaks"

            return "\(linkName(link)), \(measuredMbps) Mbps to your server; \(need)."
        }

        static func networkFix(_ link: FourKNetworkFacts.Link) -> String {
            switch link {
            case .wifi:
                "Connect the Apple TV with an Ethernet cable: Wi-Fi is the usual cause of 4K buffering. "
                    + "If that's not possible, use 5 GHz or Wi-Fi 6 close to the router."

            case .wired, .other, .offline:
                "Something between the Apple TV and the server is slow. "
                    + "Check the server's own network link and the router or switch between them."
            }
        }

        // MARK: - Player

        static let playerTitle = "Player"
        static let playerForcesConversion =
            "\"Force HDR transcode\" or \"Force Dolby Vision transcode\" is on, so HDR is converted to SDR."
        static let playerForcesConversionFix =
            "Settings › Video player › Playback quality → turn off the force HDR and Dolby Vision transcode switches."
        static let playerFix =
            "Turn on \"Use the native player for HDR and Dolby Vision\" in Settings › Video player, or pick the native player."

        static func playerDetail(chosen: VideoPlayerType, forHDR: VideoPlayerType) -> String {
            if forHDR.keepsHDR, chosen == forHDR {
                "\(chosen.displayTitle) sends HDR10 and Dolby Vision to the TV and switches it with Match Content."
            } else if forHDR.keepsHDR {
                "HDR and Dolby Vision videos open in \(forHDR.displayTitle), which keeps HDR. Others use \(chosen.displayTitle)."
            } else {
                "\(chosen.displayTitle) shows HDR videos in SDR on Apple TV. Only the native player keeps HDR10 and Dolby Vision."
            }
        }

        // MARK: - Library

        static let libraryTitle = "4K in your library"
        static let libraryEmpty = "No 4K videos in your libraries yet."
        static let libraryEmptyServerSide =
            "To get 4K, give Radarr and Sonarr a 4K quality profile. Prefer 2160p WEB-DL in HEVC with HDR10 "
                + "or Dolby Vision profile 5 or 8: they play directly here. Remuxes are much bigger and often carry "
                + "Dolby Vision profile 7 and TrueHD audio. Plan for 15–25 GB of SSD space per 4K movie."

        static func librarySummary(_ library: FourKLibraryFacts) -> String {
            let direct = library.tierCounts[.direct] ?? 0
            let light = library.tierCounts[.light] ?? 0
            let heavy = library.tierCounts[.heavy] ?? 0
            let poor = library.tierCounts[.poor] ?? 0

            var parts = ["\(direct) play directly"]

            if light > 0 {
                parts.append("\(light) need light work from your server")
            }

            if heavy > 0 {
                parts.append("\(heavy) may stutter")
            }

            if poor > 0 {
                parts.append("\(poor) will likely stutter")
            }

            let videos = library.itemCount == 1 ? "1 4K video" : "\(library.itemCount) 4K videos"
            let hdr = library.hdrCount > 0 ? " (\(library.hdrCount) HDR, \(library.dolbyVisionCount) Dolby Vision)" : ""

            return "\(videos)\(hdr) on this TV: \(parts.joined(separator: ", "))."
        }

        static func libraryPoorFix(_ count: Int) -> String {
            count == 1
                ? "Open it and tap its playback badge to see why and which copy would play directly."
                : "Open them and tap their playback badge to see why and which copy would play directly."
        }

        static let dolbyVisionProfile7Title = "Dolby Vision from disc remuxes"
        static let dolbyVisionProfile7Fix = "A WEB-DL with Dolby Vision profile 5 or 8 plays in full Dolby Vision."

        static func dolbyVisionProfile7Detail(_ count: Int) -> String {
            "\(count) use Dolby Vision profile 7, which Apple TV can't show: they play in HDR10 instead."
        }

        static let losslessAudioTitle = "TrueHD and DTS-HD audio"

        static func losslessAudioDetail(_ count: Int) -> String {
            "\(count) have TrueHD or DTS-HD audio, which the native player can't take. Your server converts the audio only: light work."
        }

        static let imageSubtitlesTitle = "Image subtitles"
        static let imageSubtitlesFix = "Pick text subtitles (SRT) when there are any, or add them with the subtitle search."

        static func imageSubtitlesDetail(_ count: Int) -> String {
            "\(count) have image subtitles (PGS or VobSub). Turning those on makes your server burn them into the 4K video: heavy work."
        }

        // MARK: - Server

        static let serverTitle = "Your server"
        static let serverLighterCopyFix = "A copy that plays directly here takes the work off your server."
    }
}
