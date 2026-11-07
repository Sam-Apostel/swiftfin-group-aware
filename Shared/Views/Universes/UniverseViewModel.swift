//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import Foundation
import JellyfinAPI
import Logging

/// One universe, plus the Jellyfin items for what's in the library (artwork, watched state).
@MainActor
final class UniverseViewModel: ObservableObject {

    @Published
    private(set) var universe: Universe?
    /// Library items by Jellyfin id, as the current person sees them.
    @Published
    private(set) var items: [String: BaseItemDto] = [:]
    @Published
    private(set) var isLoading = false
    @Published
    var error: Error?

    let universeID: String

    private let logger = Logger.swiftfin()

    init(universeID: String) {
        self.universeID = universeID
    }

    func load(force: Bool = false) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let universe = try await Container.shared.universeService().universe(id: universeID, force: force)
            self.universe = universe
            items = try await libraryItems(for: universe)
        } catch {
            if universe == nil {
                self.error = error
            }
            logger.error("Universe failed to load", metadata: ["error": .string(error.localizedDescription)])
        }
    }

    /// The person's answer about one entry ("Not part of this universe").
    func answer(entry: UniverseEntry, accept: Bool) async {
        do {
            try await Container.shared.universeService().answer(universeID: universeID, entryID: entry.id, accept: accept)
            await load(force: true)
        } catch {
            self.error = error
        }
    }

    // MARK: - Progress

    var libraryEntries: [UniverseEntry] {
        universe?.entries.filter(\.inLibrary) ?? []
    }

    var watchedCount: Int {
        libraryEntries.count { entry in
            entry.jellyfinItemId.flatMap { items[$0]?.userData?.isPlayed } == true
        }
    }

    /// The first thing in the library not watched yet, in the timeline's order.
    func nextUp(on timeline: UniverseTimeline) -> (entry: UniverseEntry, item: BaseItemDto)? {
        guard let universe else { return nil }

        for entry in UniverseLayout.ordered(universe, timeline: timeline) {
            guard let id = entry.jellyfinItemId, let item = items[id] else { continue }

            if item.userData?.isPlayed != true {
                return (entry, item)
            }
        }
        return nil
    }

    /// A backdrop for the header: the first library item that has one.
    var heroItem: BaseItemDto? {
        guard let universe else { return nil }

        let libraryItems = universe.entries.compactMap { $0.jellyfinItemId.flatMap { items[$0] } }
        return libraryItems.first { $0.backdropImageTags?.isNotEmpty == true }
    }

    // MARK: - Jellyfin

    private func libraryItems(for universe: Universe) async throws -> [String: BaseItemDto] {
        guard let session = Container.shared.currentUserSession() else { return [:] }

        let ids = universe.entries.compactMap(\.jellyfinItemId)
        var result: [String: BaseItemDto] = [:]

        for start in stride(from: 0, to: ids.count, by: 100) {
            let chunk = Array(ids[start ..< min(start + 100, ids.count)])

            var parameters = Paths.GetItemsParameters()
            parameters.ids = chunk
            parameters.limit = chunk.count
            parameters.userID = session.user.id
            parameters.enableUserData = true
            parameters.enableImages = true
            parameters.fields = PosterSubtitleField.itemFields

            let response = try await session.client.send(Paths.getItems(parameters: parameters))
            for item in response.value.items ?? [] {
                if let id = item.id {
                    result[id] = item
                }
            }
        }
        return result
    }
}
