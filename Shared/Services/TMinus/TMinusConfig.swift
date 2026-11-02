//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// Where Couchfin's problem reports, playback errors and heartbeats go: the `couchfin` project in
/// T-Minus (https://t-min.sams.works).
///
/// The key is **report-only**: it can send errors, feedback and heartbeats and nothing else, so it is
/// safe in the app bundle. Rotate it in T-Minus with `get_ingest_key` (project `couchfin`, scope
/// `report`, `rotate: true`) and paste the new one here.
enum TMinusConfig {

    static let ingestURL = URL(string: "https://t-min.sams.works/ingest/v1")!

    static let reportKey = "tm_1mToeJfSVpbBkFjpjMg3-IFxISgt8ce4"
}
