//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

extension AudienceWatchlistEntry {

    /// An entry for a Jellyfin library item (`.movie` or `.series`), or nil for any other item type.
    ///
    /// The TMDB id comes from `providerIDs["Tmdb"]`, so pass a full item
    /// (e.g. `getFullItem(userSession:)` or a query with `fields: [.providerIDs]`),
    /// otherwise the entry gets a `"jf-<itemID>"` id and won't merge with the same title added from Seerr.
    init?(item: BaseItemDto, audience: Set<String>, addedBy: String) {
        guard let kind = Self.mediaKind(of: item.type) else { return nil }

        let tmdbID = Self.tmdbID(of: item)
        let itemID = item.id.flatMap { $0.isEmpty ? nil : $0 }

        guard tmdbID != nil || itemID != nil else { return nil }

        self.init(
            tmdbID: tmdbID,
            kind: kind,
            jellyfinItemID: itemID,
            title: item.displayTitle,
            year: item.productionYear,
            posterPath: nil,
            audience: audience,
            addedBy: addedBy
        )
    }

    /// `.movie` for movies, `.tv` for series, nil otherwise.
    static func mediaKind(of type: BaseItemKind?) -> MediaKind? {
        guard let type else { return nil }

        switch type {
        case .movie:
            return .movie
        case .series:
            return .tv
        default:
            return nil
        }
    }

    /// The TMDB id of a library item (`providerIDs["Tmdb"]`, case-insensitive), if any.
    static func tmdbID(of item: BaseItemDto) -> Int? {
        guard let providerIDs = item.providerIDs else { return nil }

        let value = providerIDs.first {
            $0.key.caseInsensitiveCompare("Tmdb") == .orderedSame
        }?.value

        return value.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }
}
