//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import FactoryKit
import Foundation
import Logging

@MainActor
@Stateful
final class DiscoverViewModel: ViewModel {

    /// One horizontal Discover row. Rows that fail or come back empty are left out.
    struct Row: Identifiable {

        let category: SeerrDiscoverCategory
        let items: [SeerrMedia]

        var id: String {
            category.rawValue
        }
    }

    @CasePathable
    enum Action {
        case refresh
        case search(query: String)
        case getNextSearchPage

        var transition: Transition {
            switch self {
            case .refresh:
                .to(.refreshing, then: .content)
                    .whenBackground(.refreshing)

            case .search:
                .background(.searching)
                    .onRepeat(.cancel)

            case .getNextSearchPage:
                .background(.gettingNextSearchPage)
            }
        }
    }

    enum BackgroundState {
        case refreshing
        case searching
        case gettingNextSearchPage
    }

    enum State {
        case content
        case error
        case initial
        case refreshing
    }

    @Published
    private(set) var rows: [Row] = []
    @Published
    private(set) var searchResults: [SeerrMedia] = []
    @Published
    private(set) var searchError: Error?
    @Published
    private(set) var hasSearched: Bool = false

    /// Bound to the search field; searches are debounced by 300 ms.
    @Published
    var searchQuery: String = ""

    private var activeQuery: String = ""
    private var searchPage: Int = 0
    private var searchTotalPages: Int = 0
    private var isLoadingNextSearchPage: Bool = false

    var isSearchActive: Bool {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isNotEmpty
    }

    /// Whether anyone on the current couch is flagged as a kid (#4).
    var isKidOnCouch: Bool {
        userSession?.couch.members.contains(where: \.isKid) ?? false
    }

    private var categories: [SeerrDiscoverCategory] {
        var categories: [SeerrDiscoverCategory] = [
            .trending,
            .popularMovies,
            .popularTV,
            .upcomingMovies,
            .upcomingTV,
        ]

        if isKidOnCouch {
            categories.insert(.family, at: 0)
        }

        return categories
    }

    private var client: SeerrClient {
        get throws {
            guard let client = Container.shared.seerrService().client else {
                throw SeerrError.notConfigured
            }

            return client
        }
    }

    override init() {
        super.init()

        $searchQuery
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .removeDuplicates()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] query in
                self?.search(query: query)
            }
            .store(in: &cancellables)
    }

    // MARK: - Refresh

    @Function(\Action.Cases.refresh)
    private func _refresh() async throws {
        let seerrClient = try client

        refreshWatchlists()

        let rowCategories = categories
        var results: [SeerrDiscoverCategory: [SeerrMedia]] = [:]
        var firstError: Error?

        await withTaskGroup(of: (SeerrDiscoverCategory, Result<[SeerrMedia], Error>).self) { group in
            for category in rowCategories {
                group.addTask {
                    do {
                        let page = try await category.fetch(client: seerrClient, page: 1)
                        return (category, .success(page.results))
                    } catch {
                        return (category, .failure(error))
                    }
                }
            }

            for await (category, result) in group {
                switch result {
                case let .success(items):
                    results[category] = items
                case let .failure(error):
                    logger.error(
                        "Failed to load Seerr discover row",
                        metadata: [
                            "row": .string(category.rawValue),
                            "error": .string(error.localizedDescription),
                        ]
                    )
                    if firstError == nil {
                        firstError = error
                    }
                }
            }
        }

        guard !Task.isCancelled else { return }

        // Every row failed: surface the error so the screen can offer a retry.
        if results.isEmpty, let firstError {
            throw firstError
        }

        rows = rowCategories.compactMap { category in
            guard let items = results[category] else { return nil }

            let uniqueItems = Self.uniqued(items)
            guard uniqueItems.isNotEmpty else { return nil }

            return Row(category: category, items: uniqueItems)
        }
    }

    /// Refreshes the couch watchlist store (#9) in the background so the badges and the
    /// watchlists card are current. Never blocks or fails the Discover rows.
    private func refreshWatchlists() {
        guard let userSession else { return }

        let sessions = userSession.householdSessions()

        Task {
            await Container.shared.audienceWatchlistStore().refresh(sessions: sessions)
        }
    }

    // MARK: - Search

    @Function(\Action.Cases.search)
    private func _search(_ query: String) async {
        activeQuery = query
        searchError = nil
        searchPage = 0
        searchTotalPages = 0

        guard query.isNotEmpty else {
            searchResults = []
            hasSearched = false
            return
        }

        do {
            let page = try await client.search(query: query, page: 1)

            guard !Task.isCancelled, query == activeQuery else { return }

            searchResults = Self.uniqued(page.results)
            searchPage = page.page
            searchTotalPages = page.totalPages
            hasSearched = true
        } catch {
            guard !Self.isCancellation(error), query == activeQuery else { return }

            logger.error(
                "Seerr search failed",
                metadata: ["error": .string(error.localizedDescription)]
            )
            searchResults = []
            searchError = error
            hasSearched = true
        }
    }

    @Function(\Action.Cases.getNextSearchPage)
    private func _getNextSearchPage() async {
        let query = activeQuery

        guard query.isNotEmpty,
              searchPage > 0,
              searchPage < searchTotalPages,
              !isLoadingNextSearchPage,
              !background.is(.searching)
        else { return }

        isLoadingNextSearchPage = true
        defer { isLoadingNextSearchPage = false }

        do {
            let page = try await client.search(query: query, page: searchPage + 1)

            guard !Task.isCancelled, query == activeQuery else { return }

            let existingIDs = Set(searchResults.map(\.id))
            searchResults.append(
                contentsOf: Self.uniqued(page.results).filter { !existingIDs.contains($0.id) }
            )
            searchPage = page.page
            searchTotalPages = page.totalPages
        } catch {
            guard !Self.isCancellation(error) else { return }

            logger.error(
                "Failed to load the next Seerr search page",
                metadata: ["error": .string(error.localizedDescription)]
            )
        }
    }

    // MARK: - Helpers

    /// Grids and rows key elements by `id` (the TMDB id), so drop repeated ids.
    private static func uniqued(_ items: [SeerrMedia]) -> [SeerrMedia] {
        var seen = Set<Int>()
        return items.filter { seen.insert($0.id).inserted }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }

        return false
    }
}
