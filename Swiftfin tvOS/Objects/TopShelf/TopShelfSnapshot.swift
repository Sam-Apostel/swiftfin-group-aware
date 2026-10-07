//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// What the Top Shelf shows, written by the app for the Top Shelf extension.
///
/// The extension has a twin of this type (`Swiftfin TopShelf/TopShelfSnapshot.swift`):
/// keep both in sync. The app does all the Jellyfin work; the extension only reads this file.
struct TopShelfSnapshot: Codable {

    enum ImageShape: String, Codable {
        /// 2:3
        case poster
        /// 16:9
        case landscape
    }

    struct Item: Codable {

        /// Unique and stable within its section.
        let id: String
        let title: String
        let imageURL: URL?
        let imageShape: ImageShape
        /// 0...1, or `nil` when there is nothing to resume.
        let progress: Double?
        /// Opens the item in the app (with the right people on the couch).
        let link: URL
    }

    struct Section: Codable {

        let title: String
        let items: [Item]
    }

    let sections: [Section]
    let createdAt: Date

    /// Shared between Couchfin and its Top Shelf extension.
    static let appGroupID = "group.land.sams.swiftfin"

    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("TopShelf.json")
    }
}
