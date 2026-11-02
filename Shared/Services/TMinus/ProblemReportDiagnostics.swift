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
import UIKit

/// What's playing when someone reports a problem from the player, or when playback fails.
///
/// Only names, ids and formats: never stream URLs, which carry access tokens.
struct PlaybackReportContext {

    typealias Line = ProblemReportDiagnostics.Line

    let itemTitle: String
    let itemID: String?
    let itemType: String?
    let mediaSource: String?
    let container: String?
    let video: String?
    let audio: String?
    let subtitles: String?
    let playMethod: String
    let quality: String?
    let player: String
    let position: String?

    @MainActor
    init(manager: MediaPlayerManager) {
        let item = manager.playbackItem?.baseItem ?? manager.item

        var title = item.displayTitle
        if let seriesName = item.seriesName {
            title = [seriesName, item.seasonEpisodeLabel, item.displayTitle].compactMap(\.self).joined(separator: " · ")
        }

        self.itemTitle = title
        self.itemID = item.id
        self.itemType = item.type?.rawValue
        self.player = Defaults[.VideoPlayer.videoPlayerType].displayTitle

        let seconds = Int(manager.seconds.seconds)
        self.position = seconds > 0 ? "\(seconds / 60)m \(seconds % 60)s" : nil

        guard let playbackItem = manager.playbackItem else {
            self.mediaSource = nil
            self.container = nil
            self.video = nil
            self.audio = nil
            self.subtitles = nil
            self.playMethod = "Not started"
            self.quality = nil
            return
        }

        let source = playbackItem.mediaSource
        self.mediaSource = source.name
        self.container = source.container
        self.quality = playbackItem.requestedBitrate.displayTitle

        let selectedAudio = playbackItem.audioStreams.first { $0.index == playbackItem.selectedAudioStreamIndex }
        let selectedSubtitle = playbackItem.subtitleStreams.first { $0.index == playbackItem.selectedSubtitleStreamIndex }

        self.video = playbackItem.videoStreams.first.map(Self.describe)
        self.audio = (selectedAudio ?? playbackItem.audioStreams.first).map(Self.describe)
        self.subtitles = selectedSubtitle.map(Self.describe)

        if playbackItem.isOffline {
            self.playMethod = "Downloaded"
        } else if let transcodingURL = source.transcodingURL {
            let reasons = URLComponents(string: transcodingURL)?
                .queryItems?
                .first { $0.name == "TranscodeReasons" }?
                .value
            self.playMethod = reasons.map { "Transcode (\($0))" } ?? "Transcode"
        } else {
            self.playMethod = "Direct"
        }
    }

    private static func describe(_ stream: MediaStream) -> String {
        var parts = [stream.codec, stream.profile].compactMap(\.self)

        if let width = stream.width, let height = stream.height {
            parts.append("\(width)×\(height)")
        }
        if let language = stream.language {
            parts.append(language)
        }
        return parts.isEmpty ? "?" : parts.joined(separator: " ")
    }

    var lines: [Line] {
        let all: [Line?] = [
            Line(label: "Item", value: itemTitle),
            Line(label: "Item id", value: itemID),
            Line(label: "Type", value: itemType),
            Line(label: "Version", value: mediaSource),
            Line(label: "Container", value: container),
            Line(label: "Video", value: video),
            Line(label: "Audio", value: audio),
            Line(label: "Subtitles", value: subtitles),
            Line(label: "Play method", value: playMethod),
            Line(label: "Quality", value: quality),
            Line(label: "Player", value: player),
            Line(label: "Position", value: position),
        ]
        return all.compactMap(\.self)
    }

    /// For `POST /errors`' `extra`.
    var extra: [String: String] {
        Dictionary(lines.map { ($0.label, $0.value) }, uniquingKeysWith: { first, _ in first })
    }
}

/// The non-sensitive facts attached to a problem report: app, device, OS and Jellyfin server version.
/// The signed-in person's name is only included when they administer the server (their own server).
enum ProblemReportDiagnostics {

    struct Line: Hashable, Identifiable {

        let label: String
        let value: String

        var id: String {
            label
        }

        init?(label: String, value: String?) {
            guard let value, value.isNotEmpty else { return nil }

            self.label = label
            self.value = value
        }
    }

    @MainActor
    static func lines(playback: PlaybackReportContext?) -> [Line] {
        let device = UIDevice.current
        let session = Container.shared.userSessionManager().currentSession

        var serverVersion: String?
        var userName: String?

        if let session {
            serverVersion = StoredValues[.Server.publicInfo(id: session.server.id)].version.map { "Jellyfin \($0)" }

            if session.user.data.policy?.isAdministrator == true {
                userName = "\(session.user.username) (server admin)"
            }
        }

        let app: [Line?] = [
            Line(label: "App", value: "Couchfin \(TMinusClient.release ?? "?")"),
            Line(label: "Device", value: "\(UIDevice.platform) · \(modelIdentifier)"),
            Line(label: "OS", value: "\(device.systemName) \(device.systemVersion)"),
            Line(label: "Server", value: serverVersion),
            Line(label: "User", value: userName),
        ]

        return app.compactMap(\.self) + (playback?.lines ?? [])
    }

    /// "iPhone17,1", "AppleTV14,1".
    static var modelIdentifier: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafeBytes(of: systemInfo.machine) { buffer in
            String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    /// Appended to the report body, so it reads well in the T-Minus inbox.
    static func text(_ lines: [Line]) -> String {
        (["— Diagnostics —"] + lines.map { "\($0.label): \($0.value)" }).joined(separator: "\n")
    }
}
