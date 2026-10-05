//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// Mirrors playback progress and played state to every member on the couch.
///
/// Registered in `UserSession.services`, so it is started and stopped with the
/// primary user session. Couch member sessions are inert and never start it.
///
/// - Note: Stub. Filled in by the "Mirror progress & played state" work (#5).
@MainActor
final class CouchPlaybackService: UserSessionService {

    init() {}
}
