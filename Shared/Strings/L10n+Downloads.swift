//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// English strings for offline downloads.
extension L10n {

    enum Downloads {

        // MARK: - Tab

        static let title = "Downloads"
        static let emptyTitle = "No downloads"
        static let emptyDescription = "Download movies and episodes from their page to watch them without a connection."
        static let movies = "Movies"
        static let other = "Other"

        // MARK: - Item actions

        static let download = "Download"
        static let downloadSeason = "Download Season"
        static let downloading = "Downloading"
        static let removeDownload = "Remove Download"
        static let cancelDownload = "Cancel Download"

        // MARK: - Options

        static let quality = "Quality"
        static let qualityFooter =
            "Original keeps the file exactly as it is on the server. The other qualities ask the server to convert the video, which needs less space but takes longer to download."
        static let original = "Original"
        static let p1080 = "1080p"
        static let p720 = "720p"
        static let p480 = "480p"
        static let seasons = "Seasons"
        static let onlyUnwatched = "Only unwatched episodes"
        static let downloadAll = "Download All"

        static func availableSpace(_ size: String) -> String {
            "Available space: \(size)"
        }

        static func estimatedSize(_ size: String) -> String {
            "About \(size)"
        }

        static func episodeCount(_ count: Int) -> String {
            count == 1 ? "1 episode" : "\(count) episodes"
        }

        // MARK: - Status

        static let queued = "Waiting…"
        static let failed = "Download failed"
        static let retry = "Retry"
        static let delete = "Delete"
        static let deleteAll = "Delete All Downloads"
        static let deleteAllConfirmation = "All downloaded files will be removed from this device."

        static func storageUsed(_ size: String) -> String {
            "Storage used: \(size)"
        }

        static func progress(_ downloaded: String, _ total: String) -> String {
            "\(downloaded) of \(total)"
        }

        // MARK: - Errors

        static let noMedia = "This item has no media to download."
        static let fileMissing = "The downloaded file is missing. Delete the download and download it again."
        static let interrupted = "The download was interrupted."

        static func serverError(_ statusCode: Int) -> String {
            "The server responded with an error (\(statusCode))."
        }
    }
}
