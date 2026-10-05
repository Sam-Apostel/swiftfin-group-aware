//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// Kid-level checks for Seerr (TMDB) certifications. Foundation only.
///
/// Uses the one shared rating allowlist (`KidRatings`), so the Seerr detail screen
/// agrees with every other kid check in the app.
enum SeerrCertification {

    /// Whether a title with this certification is above what's fine for a child.
    ///
    /// Fails closed: a missing, empty or unknown certification counts as above kid level.
    static func isAboveKidLevel(_ certification: String?) -> Bool {
        !KidRatings.isKidSafe(certification)
    }
}
