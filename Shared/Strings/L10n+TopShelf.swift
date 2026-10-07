//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

// MARK: - Apple TV Top Shelf

extension L10n {

    enum TopShelf {

        /// Top Shelf row: what this couch or person is in the middle of.
        ///
        /// - Parameter who: A couch name ("🍿 Movie night"), joined names ("Sam & Lisa") or one person.
        static func continueFor(_ who: String) -> String {
            "Continue · \(who)"
        }

        /// Top Shelf row: movies and shows recently added to the server.
        static let justLanded = "Just landed"
    }
}
