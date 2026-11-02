//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

// MARK: - Facts

/// What the connected TV reports, through the Apple TV.
struct FourKDisplayFacts: Equatable {

    /// The output size in pixels.
    var width: Int
    var height: Int
    /// `AVPlayer.eligibleForHDRPlayback`.
    var isEligibleForHDR: Bool
    var supportsHDR10: Bool
    var supportsDolbyVision: Bool
    /// Match Content (dynamic range or frame rate), `nil` when unknown.
    var matchesContent: Bool?

    var is4K: Bool {
        width >= 3800
    }
}

/// How the Apple TV reaches the Jellyfin server.
struct FourKNetworkFacts: Equatable {

    enum Link: Equatable {
        case wired
        case wifi
        case other
        case offline
    }

    var link: Link
    /// Measured with the server's bitrate test, `nil` when it failed.
    var measuredMbps: Int?
}

/// Which player 4K HDR videos open in.
struct FourKPlayerFacts: Equatable {

    var chosen: VideoPlayerType
    var prefersNativeForHDR: Bool
    var forcesHDRConversion: Bool
    var forcesDolbyVisionConversion: Bool

    /// The player an HDR video opens in on an HDR screen.
    var playerForHDR: VideoPlayerType {
        VideoPlayerType.forPlayback(chosen: chosen, prefersNativeForHDR: prefersNativeForHDR, displaysHDR: true, isHDRVideo: true)
    }
}

/// A summary of the 4K videos in the user's libraries.
struct FourKLibraryFacts: Equatable {

    var itemCount: Int
    var hdrCount: Int
    var dolbyVisionCount: Int
    var tierCounts: [PlaybackHealthTier: Int]
    /// Dolby Vision profile 7, typical of disc remuxes.
    var dolbyVisionProfile7Count: Int
    /// TrueHD or DTS-HD audio, which the native player can't take.
    var losslessAudioCount: Int
    /// Image subtitles (PGS, VobSub), burned into the video when turned on.
    var imageSubtitleCount: Int
    var highestMbps: Int?
    /// The hardest video conversion among them, when any video must be converted.
    var hardestConversion: PlaybackHealthVerdict?

    static let empty = FourKLibraryFacts(
        itemCount: 0,
        hdrCount: 0,
        dolbyVisionCount: 0,
        tierCounts: [:],
        dolbyVisionProfile7Count: 0,
        losslessAudioCount: 0,
        imageSubtitleCount: 0,
        highestMbps: nil,
        hardestConversion: nil
    )
}

// MARK: - Checklist

enum FourKReadinessStatus: Equatable {

    case ready
    case fix
    /// Worth knowing, nothing to fix.
    case note
}

struct FourKReadinessRow: Equatable, Identifiable {

    enum Kind: String {
        case resolution
        case hdr
        case matchContent
        case network
        case player
        case library
        case dolbyVisionProfile7
        case losslessAudio
        case imageSubtitles
        case server
    }

    var kind: Kind
    var status: FourKReadinessStatus
    var title: String
    var detail: String
    var fix: String?

    var id: String {
        kind.rawValue
    }
}

/// Pure: turns the facts into checklist rows with plain words.
enum FourKReadiness {

    /// Typical bitrates: 4K WEB-DL averages 15-40 Mbps, 4K remuxes 50-100 Mbps with peaks.
    static let webDLMbps = 40
    static let remuxMbps = 100
    /// Room for bitrate peaks on top of a file's average.
    static let peakHeadroom = 1.25

    static func rows(
        display: FourKDisplayFacts?,
        network: FourKNetworkFacts,
        player: FourKPlayerFacts,
        library: FourKLibraryFacts?
    ) -> [FourKReadinessRow] {
        var rows: [FourKReadinessRow] = []
        typealias Strings = L10n.FourKReadiness

        if let display {
            rows.append(
                FourKReadinessRow(
                    kind: .resolution,
                    status: display.is4K ? .ready : .fix,
                    title: Strings.resolutionTitle,
                    detail: Strings.resolutionDetail(width: display.width, height: display.height),
                    fix: display.is4K ? nil : Strings.resolutionFix
                )
            )

            rows.append(
                FourKReadinessRow(
                    kind: .hdr,
                    status: display.isEligibleForHDR ? .ready : .fix,
                    title: Strings.hdrTitle,
                    detail: Strings.hdrDetail(display),
                    fix: display.isEligibleForHDR ? nil : Strings.hdrFix
                )
            )

            rows.append(
                FourKReadinessRow(
                    kind: .matchContent,
                    status: display.matchesContent == false ? .fix : (display.matchesContent == true ? .ready : .note),
                    title: Strings.matchContentTitle,
                    detail: Strings.matchContentDetail(display.matchesContent),
                    fix: display.matchesContent == false ? Strings.matchContentFix : nil
                )
            )
        }

        rows.append(networkRow(network, highestMbps: library?.highestMbps))
        rows.append(playerRow(player))

        if let library {
            rows.append(contentsOf: libraryRows(library))
        }

        return rows
    }

    /// The one-line answer: ready, or how many things to fix.
    static func fixCount(_ rows: [FourKReadinessRow]) -> Int {
        rows.reduce(0) { total, row in row.status == .fix ? total + 1 : total }
    }

    // MARK: - Network

    /// The bitrate the network should carry: the highest file in the library with room for peaks,
    /// or a typical 4K WEB-DL when there's no 4K yet.
    static func neededMbps(highestMbps: Int?) -> Int {
        guard let highestMbps, highestMbps > 0 else { return webDLMbps }

        return Int((Double(highestMbps) * peakHeadroom).rounded())
    }

    static func networkRow(_ network: FourKNetworkFacts, highestMbps: Int?) -> FourKReadinessRow {
        typealias Strings = L10n.FourKReadiness

        let needed = neededMbps(highestMbps: highestMbps)

        guard network.link != .offline, let measured = network.measuredMbps else {
            return FourKReadinessRow(
                kind: .network,
                status: network.link == .offline ? .fix : .note,
                title: Strings.networkTitle,
                detail: Strings.networkUnmeasured(network.link),
                fix: network.link == .offline ? Strings.networkOfflineFix : nil
            )
        }

        let isEnough = measured >= needed

        return FourKReadinessRow(
            kind: .network,
            status: isEnough ? .ready : .fix,
            title: Strings.networkTitle,
            detail: Strings.networkDetail(
                link: network.link,
                measuredMbps: measured,
                neededMbps: needed,
                hasLibraryFigure: highestMbps != nil
            ),
            fix: isEnough ? nil : Strings.networkFix(network.link)
        )
    }

    // MARK: - Player

    static func playerRow(_ player: FourKPlayerFacts) -> FourKReadinessRow {
        typealias Strings = L10n.FourKReadiness

        if player.forcesHDRConversion || player.forcesDolbyVisionConversion {
            return FourKReadinessRow(
                kind: .player,
                status: .fix,
                title: Strings.playerTitle,
                detail: Strings.playerForcesConversion,
                fix: Strings.playerForcesConversionFix
            )
        }

        let hdrPlayer = player.playerForHDR

        return FourKReadinessRow(
            kind: .player,
            status: hdrPlayer.keepsHDR ? .ready : .fix,
            title: Strings.playerTitle,
            detail: Strings.playerDetail(chosen: player.chosen, forHDR: hdrPlayer),
            fix: hdrPlayer.keepsHDR ? nil : Strings.playerFix
        )
    }

    // MARK: - Library

    static func libraryRows(_ library: FourKLibraryFacts) -> [FourKReadinessRow] {
        typealias Strings = L10n.FourKReadiness

        guard library.itemCount > 0 else {
            return [
                FourKReadinessRow(
                    kind: .library,
                    status: .note,
                    title: Strings.libraryTitle,
                    detail: Strings.libraryEmpty,
                    fix: Strings.libraryEmptyServerSide
                ),
            ]
        }

        let poorCount = library.tierCounts[.poor] ?? 0

        var rows = [
            FourKReadinessRow(
                kind: .library,
                status: poorCount > 0 ? .fix : .ready,
                title: Strings.libraryTitle,
                detail: Strings.librarySummary(library),
                fix: poorCount > 0 ? Strings.libraryPoorFix(poorCount) : nil
            ),
        ]

        if library.dolbyVisionProfile7Count > 0 {
            rows.append(
                FourKReadinessRow(
                    kind: .dolbyVisionProfile7,
                    status: .note,
                    title: Strings.dolbyVisionProfile7Title,
                    detail: Strings.dolbyVisionProfile7Detail(library.dolbyVisionProfile7Count),
                    fix: Strings.dolbyVisionProfile7Fix
                )
            )
        }

        if library.losslessAudioCount > 0 {
            rows.append(
                FourKReadinessRow(
                    kind: .losslessAudio,
                    status: .note,
                    title: Strings.losslessAudioTitle,
                    detail: Strings.losslessAudioDetail(library.losslessAudioCount),
                    fix: nil
                )
            )
        }

        if library.imageSubtitleCount > 0 {
            rows.append(
                FourKReadinessRow(
                    kind: .imageSubtitles,
                    status: .note,
                    title: Strings.imageSubtitlesTitle,
                    detail: Strings.imageSubtitlesDetail(library.imageSubtitleCount),
                    fix: Strings.imageSubtitlesFix
                )
            )
        }

        if let hardest = library.hardestConversion, let server = hardest.server, let streamClass = hardest.streamClass {
            let isFine = hardest.tier <= .light

            rows.append(
                FourKReadinessRow(
                    kind: .server,
                    status: isFine ? .ready : .fix,
                    title: Strings.serverTitle,
                    detail: L10n.PlaybackHealth.serverDescription(server, streamClass: streamClass),
                    fix: isFine ? nil : (L10n.PlaybackHealth.serverFix(server) ?? Strings.serverLighterCopyFix)
                )
            )
        }

        return rows
    }

    // MARK: - Library scan

    /// Folds one 4K video into the summary.
    static func adding(
        _ source: MediaSourceInfo,
        verdict: PlaybackHealthVerdict?,
        to library: FourKLibraryFacts
    ) -> FourKLibraryFacts {
        var library = library
        let streams = source.mediaStreams ?? []
        let video = streams.first { $0.type == .video }
        let audio = streams.first { $0.type == .audio && $0.index == source.defaultAudioStreamIndex }
            ?? streams.first { $0.type == .audio }

        library.itemCount += 1

        if video?.videoRangeType?.isHDR == true {
            library.hdrCount += 1
        }

        if video?.videoRangeType?.isDolbyVision == true {
            library.dolbyVisionCount += 1
        }

        if video?.dvProfile == 7 {
            library.dolbyVisionProfile7Count += 1
        }

        if isLosslessAudio(audio) {
            library.losslessAudioCount += 1
        }

        if streams.contains(where: { $0.type == .subtitle && $0.isTextSubtitleStream == false }) {
            library.imageSubtitleCount += 1
        }

        if let bitrate = source.bitrate {
            library.highestMbps = max(library.highestMbps ?? 0, PlaybackHealthClassifier.megabits(bitrate))
        }

        if let verdict {
            library.tierCounts[verdict.tier, default: 0] += 1

            if verdict.reencodesVideo, verdict.tier > (library.hardestConversion?.tier ?? .direct) || library.hardestConversion == nil {
                library.hardestConversion = verdict
            }
        }

        return library
    }

    /// TrueHD (with or without Atmos) or DTS-HD. AVPlayer takes neither, so the server converts the audio.
    static func isLosslessAudio(_ stream: MediaStream?) -> Bool {
        let codec = stream?.codec?.lowercased() ?? ""
        let profile = stream?.profile?.lowercased() ?? ""

        return codec == "truehd" || codec == "mlp" || (codec == "dts" && profile.contains("hd"))
    }
}
