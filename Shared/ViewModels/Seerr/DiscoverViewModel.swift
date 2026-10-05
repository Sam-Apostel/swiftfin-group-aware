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

    /// Whether the current search results went through the kid-mode filter
    /// (`SeerrFamilySearchFilter`), so the screen can say why titles are missing.
    @Published
    private(set) var isFamilyFiltered: Bool = false

    /// The couch of the current session, read live so a couch change is picked up.
    private var couch: CouchGroup? {
        Container.shared.currentUserSession()?.couch ?? userSession?.couch
    }

    /// Kid mode (#49): a child is on the couch (`CouchGroup.hasChild`: marked as a kid,
    /// or a server age limit below 12). Deliberately independent of Kid-safe browsing.
    ///
    /// Fails closed: without a couch, Discover stays kid-safe.
    var isKidMode: Bool {
        couch?.hasChild ?? true
    }

    /// The names of the children on the couch, in couch order, for the kid-mode footer.
    var childMemberNames: [String] {
        couch?.members.filter(\.isChildAudience).map(\.username) ?? []
    }

    /// Kid mode shows only the kid-safe rows; the grown-up rows come back once no child is on the couch.
    private var categories: [SeerrDiscoverCategory] {
        SeerrDiscoverCategory.rows(isKidMode: isKidMode)
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
            isFamilyFiltered = false
            hasSearched = false
            return
        }

        let filtersForKids = isKidMode

        do {
            let load = try await loadSearchPages(query: query, from: 1, familyOnly: filtersForKids)

            guard !Task.isCancelled, query == activeQuery else { return }

            searchResults = Self.uniqued(load.results)
            searchPage = load.page
            searchTotalPages = load.totalPages
            isFamilyFiltered = filtersForKids
            hasSearched = true
        } catch {
            guard !Self.isCancellation(error), query == activeQuery else { return }

            logger.error(
                "Seerr search failed",
                metadata: ["error": .string(error.localizedDescription)]
            )
            searchResults = []
            isFamilyFiltered = filtersForKids
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

        // Never loosen the filter mid-search; tighten it when a child just joined the couch
        let filtersForKids = isFamilyFiltered || isKidMode

        do {
            let load = try await loadSearchPages(query: query, from: searchPage + 1, familyOnly: filtersForKids)

            guard !Task.isCancelled, query == activeQuery else { return }

            if filtersForKids, !isFamilyFiltered {
                searchResults = SeerrFamilySearchFilter.familyPicks(searchResults)
                isFamilyFiltered = true
            }

            let existingIDs = Set(searchResults.map(\.id))
            searchResults.append(
                contentsOf: Self.uniqued(load.results).filter { !existingIDs.contains($0.id) }
            )
            searchPage = load.page
            searchTotalPages = load.totalPages
        } catch {
            guard !Self.isCancellation(error) else { return }

            logger.error(
                "Failed to load the next Seerr search page",
                metadata: ["error": .string(error.localizedDescription)]
            )
        }
    }

    /// Search pages loaded in one go.
    private struct SearchLoad {
        let results: [SeerrMedia]
        let page: Int
        let totalPages: Int
    }

    /// In kid mode, at most this many search pages are loaded in one go to find a family pick.
    private static let maxFamilyFilteredPagesPerLoad = 3

    /// Loads search results from page `startPage`.
    ///
    /// With `familyOnly`, only family picks (`SeerrFamilySearchFilter`) are kept, and
    /// pages that keep nothing are skipped (up to `maxFamilyFilteredPagesPerLoad`), so a
    /// page of grown-up titles doesn't end the search at "No results" or stall paging.
    private func loadSearchPages(query: String, from startPage: Int, familyOnly: Bool) async throws -> SearchLoad {
        let seerrClient = try client
        let maxPages = familyOnly ? Self.maxFamilyFilteredPagesPerLoad : 1

        var page = startPage
        var results: [SeerrMedia] = []
        var loadedPage = startPage
        var totalPages = startPage

        for _ in 0 ..< maxPages {
            let response = try await seerrClient.search(query: query, page: page)

            try Task.checkCancellation()

            loadedPage = response.page
            totalPages = response.totalPages
            results.append(
                contentsOf: familyOnly ? SeerrFamilySearchFilter.familyPicks(response.results) : response.results
            )

            guard results.isEmpty, response.page < response.totalPages else { break }

            page = response.page + 1
        }

        return SearchLoad(results: results, page: loadedPage, totalPages: totalPages)
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
