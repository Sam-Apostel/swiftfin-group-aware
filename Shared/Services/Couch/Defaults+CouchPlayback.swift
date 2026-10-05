//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Foundation
import JellyfinAPI

extension Defaults.Keys.Couch {

    /// Next-episode autoplay when several people watch together, on this device.
    ///
    /// `nil` follows the Jellyfin setting of the first person picked for the couch.
    /// Toggling autoplay in the player on a group couch sets this value and never changes
    /// anyone's server account: kid-safe browsing can make a kid the session user.
    static let autoPlayNextEpisode = Defaults.Key<Bool?>("couchAutoPlayNextEpisode", suite: .appSuite)
}

/// Next-episode autoplay for the couch.
///
/// - Solo: the session user's Jellyfin setting, as before.
/// - Group: `Defaults[.Couch.autoPlayNextEpisode]`, else the Jellyfin setting of the first person picked
///   (never the kid-safe primary, unless they were picked first).
enum CouchAutoPlay {

    /// Whether the next episode plays automatically for this session.
    static func isNextEpisodeEnabled(in userSession: UserSession) -> Bool {
        let couch = userSession.couch

        guard couch.isGroup else {
            return userSession.user.data.configuration?.enableNextEpisodeAutoPlay == true
        }

        return Defaults[.Couch.autoPlayNextEpisode] ?? firstPickSetting(for: couch)
    }

    /// The Jellyfin autoplay setting of the first person picked for a group couch.
    static func firstPickSetting(for couch: CouchGroup) -> Bool {
        firstPick(of: couch)?.data.configuration?.enableNextEpisodeAutoPlay == true
    }

    /// The first person picked for the couch, from the stored pick order.
    ///
    /// Falls back to the first member who isn't a kid, then to the primary user.
    static func firstPick(of couch: CouchGroup) -> UserState? {
        let memberIDs = couch.memberIDs

        if let firstID = Defaults[.Couch.lastMemberIDs].first(where: { memberIDs.contains($0) }),
           let member = couch.members.first(where: { $0.id == firstID })
        {
            return member
        }

        return couch.members.first { !$0.isKid } ?? couch.primary
    }
}
