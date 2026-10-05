//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// English strings for the tvOS Seerr media detail screen (#32).
/// Kept out of the generated `Strings.swift` to avoid merge conflicts.
/// The shared detail strings live in `L10n.SeerrDetail`.
extension L10n {

    enum SeerrTVDetail {

        /// Shown instead of the Request button when only kids are on the couch.
        static let askAGrownUp = "Ask a grown-up to request it"

        /// "Requesting as Sam": the request goes out as another couch member than the primary user.
        static func requestingAs(_ name: String) -> String {
            "Requesting as \(name)"
        }

        /// "Signing in Sam…": the requester gets a Seerr session (Quick Connect) before the request.
        static func signingIn(_ name: String) -> String {
            "Signing in \(name)…"
        }

        /// "Starring A, B, C".
        static func starring(_ names: String) -> String {
            "Starring \(names)"
        }
    }
}
