//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

// Strings for the "Watchlists" screen (#15). English only for now, kept in
// a feature file so the generated `.strings` file is not touched.

extension L10n {

    enum Watchlists {

        static let title = "Watchlists"

        // MARK: - Empty states

        static let emptyTitle = "Nothing here yet"
        static let emptyDescription = "Tap \u{201C}Who\u{2019}s it for?\u{201D} on any movie or show."
        static let noMatchesTitle = "No matches"
        static let noMatchesDescription = "Nothing on your watchlists matches this filter."

        // MARK: - Filter

        static let filter = "Show"
        static let filterAll = "All"
        static let filterAvailable = "Available now"
        static let filterNotAvailable = "Not yet available"

        // MARK: - Availability

        static let inLibrary = "In library"
        static let requested = "Requested"
        static let notRequested = "Not requested"
        static let notInLibrary = "Not in library"

        // MARK: - Actions

        static let remove = "Remove"
        static let changeWho = "Change who"
        static let whoIsItFor = "Who\u{2019}s it for?"
        static let removed = "Removed from watchlist"
        static let updated = "Watchlist updated"

        static func itemCount(_ count: Int) -> String {
            count == 1 ? "1 title" : "\(count) titles"
        }
    }
}
