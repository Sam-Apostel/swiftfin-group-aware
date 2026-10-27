//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

/// A downloaded (or downloading) item, persisted as `record.json` next to its media file.
struct DownloadRecord: Codable, Hashable, Identifiable {

    enum Status: String, Codable {
        case queued
        case downloading
        case completed
        case failed
    }

    /// The Jellyfin item ID.
    let id: String

    let serverID: String
    let userID: String

    /// The full item, captured when the download started, so it can be shown and played offline.
    var item: BaseItemDto
    /// The media source as it is in the downloaded file.
    var mediaSource: MediaSourceInfo

    let quality: DownloadQuality
    var status: Status

    /// File name of the media inside the record's folder.
    var mediaFileName: String?
    /// File name of the poster image inside the record's folder.
    var imageFileName: String?

    var bytesWritten: Int64 = 0
    /// Expected size. May be an estimate while a transcoded download is in progress.
    var bytesExpected: Int64?

    var dateAdded: Date
    var errorMessage: String?

    // MARK: Offline progress

    /// The last playback position reached while playing the download.
    var playbackPositionTicks: Int?
    var isPlayed: Bool?
    /// Whether local playback progress has not been sent to the server yet.
    var hasPendingProgressSync: Bool = false

    var displayTitle: String {
        item.displayTitle
    }

    var progress: Double? {
        guard let bytesExpected, bytesExpected > 0 else { return nil }

        return min(1, Double(bytesWritten) / Double(bytesExpected))
    }

    /// The item to use for playback, with the locally saved progress applied.
    var playbackItem: BaseItemDto {
        var item = item

        if item.userData == nil {
            item.userData = UserItemDataDto(key: "")
        }

        if let playbackPositionTicks {
            item.userData?.playbackPositionTicks = playbackPositionTicks
        }

        if let isPlayed {
            item.userData?.isPlayed = isPlayed
        }

        return item
    }
}
