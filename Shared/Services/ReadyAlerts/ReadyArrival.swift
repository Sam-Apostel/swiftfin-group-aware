//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// A household wish that became playable: "Toy Story is ready for Sam, Lisa & Tuur".
///
/// Foundation only: this file is type-checked on Linux.
/// There is at most one arrival per Jellyfin item.
struct ReadyArrival: Hashable, Identifiable, Sendable {

    enum Source: String, Hashable, Sendable {
        /// A "Who's it for?" watchlist entry.
        case watchlist
        /// A Seerr request without a watchlist entry, or a series request newer than its entry (a new season).
        case seerrRequest
    }

    /// `"w:<watchlist entry id>"` or `"r:<seerr request id>"`.
    let id: String
    let source: Source
    let watchlistEntryID: String?
    let jellyfinItemID: String
    /// The Jellyfin item's `displayTitle`.
    let title: String
    /// Jellyfin user ids.
    let audience: Set<String>
    /// When it was wished for: the watchlist entry's `addedAt`, or the Seerr request's `createdAt`.
    let wishedAt: Date
    /// When it landed in the library.
    let arrivedAt: Date
}

extension ReadyArrival {

    /// The arrival id of a watchlist entry.
    static func watchlistID(entryID: String) -> String {
        "w:\(entryID)"
    }

    /// The arrival id of a Seerr request.
    static func requestID(_ requestID: Int) -> String {
        "r:\(requestID)"
    }
}
