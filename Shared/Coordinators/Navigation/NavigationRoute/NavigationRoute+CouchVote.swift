//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

extension NavigationRoute {

    /// "Vote for tonight": the host (TV) side of a couch vote.
    ///
    /// - Parameters:
    ///   - candidates: the decider's upcoming cards, in deck order (up to 5).
    ///     The screen lets the couch pick 3, 4 or 5 of them before sending.
    ///   - items: `candidate.id` → item, for posters and playback.
    @MainActor
    static func couchVote(
        couch: CouchGroup,
        candidates: [CouchDeciderCandidate],
        items: [String: BaseItemDto]
    ) -> NavigationRoute {
        NavigationRoute(
            id: "couchVote",
            style: .fullscreen
        ) {
            CouchVoteHostView(
                couch: couch,
                candidates: candidates,
                items: items
            )
        }
    }
}
