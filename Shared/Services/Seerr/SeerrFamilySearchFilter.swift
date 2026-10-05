//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// The kid-mode filter for Seerr search results (#49). Foundation only.
///
/// TMDB search has no certification filter, so kid mode keeps a result only when its
/// TMDB genres say it's made for families:
/// - movies need Family (10751),
/// - shows need Family (10751) or Kids (10762).
///
/// Animation (16) alone is not enough: Sausage Party, adult anime and BoJack are all Animation.
/// It fails closed: results without `genreIds` are dropped. People and collections never
/// get here, because `SeerrMedia` only decodes movies and shows.
enum SeerrFamilySearchFilter {

    static let familyGenreID = 10751
    static let kidsGenreID = 10762

    /// Whether a search result of `mediaType` with these TMDB genres is shown in kid mode.
    static func isFamilyPick(mediaType: SeerrMediaType, genreIDs: [Int]?) -> Bool {
        guard let genreIDs, genreIDs.isEmpty == false else { return false }

        switch mediaType {
        case .movie:
            return genreIDs.contains(familyGenreID)
        case .tv:
            return genreIDs.contains(familyGenreID) || genreIDs.contains(kidsGenreID)
        }
    }

    /// The results that are shown in kid mode, in their original order.
    static func familyPicks(_ results: [SeerrMedia]) -> [SeerrMedia] {
        results.filter { isFamilyPick(mediaType: $0.mediaType, genreIDs: $0.genreIds) }
    }
}
