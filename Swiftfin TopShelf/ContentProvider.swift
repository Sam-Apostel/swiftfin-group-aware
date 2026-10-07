//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import TVServices

/// Couchfin's Top Shelf: rows of what each couch and each person is in the middle of,
/// and what just landed on the server. The app writes the rows (see `TopShelfSnapshot`);
/// when there's nothing yet, the system shows the static Top Shelf image.
final class ContentProvider: TVTopShelfContentProvider {

    override func loadTopShelfContent() async -> (any TVTopShelfContent)? {
        guard let url = TopShelfSnapshot.fileURL,
              let data = try? Data(contentsOf: url),
              let snapshot = try? Self.decoder.decode(TopShelfSnapshot.self, from: data)
        else { return nil }

        let sections = snapshot.sections.compactMap(Self.collection)

        guard sections.isNotEmpty else { return nil }

        return TVTopShelfSectionedContent(sections: sections)
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static func collection(_ section: TopShelfSnapshot.Section) -> TVTopShelfItemCollection<TVTopShelfSectionedItem>? {
        let items = section.items.map { item in
            let topShelfItem = TVTopShelfSectionedItem(identifier: section.title + "/" + item.id)
            topShelfItem.title = item.title
            topShelfItem.imageShape = item.imageShape == .poster ? .poster : .hdtv
            topShelfItem.setImageURL(item.imageURL, for: .screenScale1x)
            topShelfItem.setImageURL(item.imageURL, for: .screenScale2x)

            if let progress = item.progress {
                topShelfItem.playbackProgress = progress
            }

            let action = TVTopShelfAction(url: item.link)
            topShelfItem.displayAction = action
            topShelfItem.playAction = action

            return topShelfItem
        }

        guard items.isNotEmpty else { return nil }

        let collection = TVTopShelfItemCollection(items: items)
        collection.title = section.title
        return collection
    }
}

private extension Array {

    var isNotEmpty: Bool {
        !isEmpty
    }
}
