//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// The quality an item is downloaded in.
///
/// `original` downloads the source file as-is. Every other quality asks
/// the server to transcode to H.264/AAC in an MP4 container, which every
/// player can open and is much smaller.
enum DownloadQuality: String, CaseIterable, Codable, Displayable, Identifiable {

    case original
    case p1080
    case p720
    case p480

    var id: String {
        rawValue
    }

    var displayTitle: String {
        switch self {
        case .original:
            L10n.Downloads.original
        case .p1080:
            L10n.Downloads.p1080
        case .p720:
            L10n.Downloads.p720
        case .p480:
            L10n.Downloads.p480
        }
    }

    var isTranscoded: Bool {
        self != .original
    }

    var maxWidth: Int? {
        switch self {
        case .original:
            nil
        case .p1080:
            1920
        case .p720:
            1280
        case .p480:
            854
        }
    }

    /// Video bitrate, in bits per second.
    var videoBitrate: Int? {
        switch self {
        case .original:
            nil
        case .p1080:
            8_000_000
        case .p720:
            4_000_000
        case .p480:
            1_500_000
        }
    }

    /// Audio bitrate, in bits per second.
    static let audioBitrate = 192_000

    /// Rough size of an item in bytes, for display before a download starts.
    func estimatedSize(runtimeSeconds: Double, sourceSize: Int?, sourceBitrate: Int?) -> Int? {
        switch self {
        case .original:
            if let sourceSize, sourceSize > 0 {
                return sourceSize
            }
            guard let sourceBitrate, runtimeSeconds > 0 else { return nil }

            return Int(Double(sourceBitrate) / 8 * runtimeSeconds)

        default:
            guard let videoBitrate, runtimeSeconds > 0 else { return nil }

            // Never larger than the source when the source is already smaller
            var bitrate = videoBitrate + Self.audioBitrate
            if let sourceBitrate, sourceBitrate > 0 {
                bitrate = min(bitrate, sourceBitrate)
            }
            return Int(Double(bitrate) / 8 * runtimeSeconds)
        }
    }
}
