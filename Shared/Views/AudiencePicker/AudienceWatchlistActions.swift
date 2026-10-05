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

/// Glue between Jellyfin library items, the current couch and the
/// audience watchlist store, shared by the item action button,
/// the poster context menu and the item header label.
@MainActor
enum AudienceWatchlistActions {

    enum Outcome {
        case saved(Set<String>)
        case removed
    }

    private static let logger = Logger.swiftfin()
    private static let refreshInterval: TimeInterval = 60
    private static var lastRefresh: Date?

    // MARK: - Lookup

    static func supports(_ item: BaseItemDto) -> Bool {
        guard item.id != nil else { return false }

        return item.type == .movie || item.type == .series
    }

    /// The entry for a library item: by its watchlist id (TMDB based when the item has a TMDB id),
    /// falling back to any entry that references the Jellyfin item id.
    static func entry(
        for item: BaseItemDto,
        in store: AudienceWatchlistStore
    ) -> AudienceWatchlistEntry? {
        if let probe = AudienceWatchlistEntry(item: item, audience: [], addedBy: ""),
           let entry = store.entry(id: probe.id)
        {
            return entry
        }

        guard let itemID = item.id else { return nil }

        return store.entries.first { $0.jellyfinItemID == itemID }
    }

    static func entry(for item: BaseItemDto) -> AudienceWatchlistEntry? {
        entry(for: item, in: Container.shared.audienceWatchlistStore())
    }

    /// Pre-selection for the picker: the existing audience, else the current couch.
    static func initialAudience(for item: BaseItemDto) -> Set<String> {
        if let entry = entry(for: item) {
            return entry.audience
        }

        return Container.shared.currentUserSession()?.couch.memberIDs ?? []
    }

    // MARK: - Users

    static func householdSessions() -> [UserSession] {
        Container.shared.currentUserSession()?.householdSessions() ?? []
    }

    /// Every stored user on the current server, current user first.
    /// Cheap (no keychain access), used to render labels.
    static func serverUsers() -> [UserState] {
        guard let userSession = Container.shared.currentUserSession() else { return [] }

        let others = StoredValues[.User.users]
            .filter { $0.serverID == userSession.server.id && $0.id != userSession.user.id }

        return [userSession.user] + others
    }

    // MARK: - Store

    /// Refreshes the store at most once a minute, so item views stay cheap to open.
    static func refreshIfNeeded() async {
        let store = Container.shared.audienceWatchlistStore()

        // Skip when this helper or anyone else (e.g. the home rows) refreshed recently
        let lastDates = [lastRefresh, store.lastRefreshDate].compactMap(\.self)
        if lastDates.contains(where: { Date.now.timeIntervalSince($0) < refreshInterval }) {
            return
        }

        guard !store.isRefreshing else { return }

        let sessions = householdSessions()
        guard sessions.isNotEmpty else { return }

        lastRefresh = .now
        await store.refresh(sessions: sessions)
    }

    static func save(item: BaseItemDto, audience: Set<String>) async throws {
        guard let userSession = Container.shared.currentUserSession() else {
            throw ErrorMessage(L10n.unknownError)
        }

        let store = Container.shared.audienceWatchlistStore()
        let newEntry: AudienceWatchlistEntry

        if var existing = entry(for: item, in: store) {
            existing.audience = audience
            existing.jellyfinItemID = existing.jellyfinItemID ?? item.id
            newEntry = existing
        } else if let created = AudienceWatchlistEntry(
            item: item,
            audience: audience,
            addedBy: userSession.user.id
        ) {
            newEntry = created
        } else {
            throw ErrorMessage(L10n.unknownError)
        }

        try await store.upsert(newEntry, sessions: householdSessions())
    }

    static func remove(item: BaseItemDto) async throws {
        let store = Container.shared.audienceWatchlistStore()

        guard let existing = entry(for: item, in: store) else { return }

        try await store.remove(entryID: existing.id, sessions: householdSessions())
    }

    /// Runs a save or remove after the picker was dismissed and reports the outcome.
    static func perform(
        _ outcome: Outcome,
        item: BaseItemDto,
        completion: ((Result<Outcome, Error>) -> Void)?
    ) {
        Task { @MainActor in
            do {
                switch outcome {
                case let .saved(audience):
                    try await save(item: item, audience: audience)
                case .removed:
                    try await remove(item: item)
                }

                completion?(.success(outcome))
            } catch {
                logger.error(
                    "Unable to update the audience watchlist",
                    metadata: ["error": .string(error.localizedDescription)]
                )
                completion?(.failure(error))
            }
        }
    }
}
