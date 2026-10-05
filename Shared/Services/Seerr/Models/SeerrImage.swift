//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// TMDB image URLs for Seerr paths. No TMDB key is needed.
///
/// Documented sizes:
/// - posters: `w92`, `w154`, `w185`, `w342`, `w500`, `w780`, `original`
/// - backdrops: `w300`, `w780`, `w1280`, `original`
/// - profiles: `w45`, `w185`, `h632`
enum SeerrImage {

    static let baseURL = "https://image.tmdb.org/t/p/"

    /// `https://image.tmdb.org/t/p/<size><path>`.
    ///
    /// Absolute `http(s)` paths (e.g. TVDB artwork) are passed through unchanged.
    /// Returns `nil` for `nil` or blank paths.
    static func url(_ path: String?, size: String = "w342") -> URL? {
        guard let path = path?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
            return nil
        }

        let lowercased = path.lowercased()

        if lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://") {
            return URL(string: path)
        }

        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"

        return URL(string: "\(baseURL)\(size)\(normalizedPath)")
    }
}
