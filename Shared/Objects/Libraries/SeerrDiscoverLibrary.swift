//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import Foundation

/// A Discover row backed by one of the paged Seerr discover endpoints.
enum SeerrDiscoverCategory: String, CaseIterable, Hashable, Sendable {

    case family
    case trending
    case popularMovies
    case popularTV
    case upcomingMovies
    case upcomingTV

    var displayTitle: String {
        switch self {
        case .family:
            L10n.SeerrDiscover.familyMovieNight
        case .trending:
            L10n.SeerrDiscover.trending
        case .popularMovies:
            L10n.SeerrDiscover.popularMovies
        case .popularTV:
            L10n.SeerrDiscover.popularShows
        case .upcomingMovies:
            L10n.SeerrDiscover.upcomingMovies
        case .upcomingTV:
            L10n.SeerrDiscover.upcomingShows
        }
    }

    var systemImage: String {
        switch self {
        case .family:
            "figure.and.child.holdinghands"
        case .trending:
            "flame.fill"
        case .popularMovies:
            "film"
        case .popularTV:
            "tv"
        case .upcomingMovies, .upcomingTV:
            "calendar"
        }
    }

    func fetch(client: SeerrClient, page: Int) async throws -> SeerrPage<SeerrMedia> {
        switch self {
        case .family:
            try await client.familyMovies(page: page)
        case .trending:
            try await client.trending(page: page)
        case .popularMovies:
            try await client.popularMovies(page: page)
        case .popularTV:
            try await client.popularTV(page: page)
        case .upcomingMovies:
            try await client.upcomingMovies(page: page)
        case .upcomingTV:
            try await client.upcomingTV(page: page)
        }
    }
}

/// The "see all" grid of a Discover row, rendered by `PagingLibraryView`.
///
/// Seerr pages are fixed at 20 results, while `PagingLibraryViewModel` asks for
/// `pageSize` (50) elements per call and stops when it gets fewer. Each call therefore
/// fetches as many Seerr pages as needed to fill `pageSize`.
struct SeerrDiscoverLibrary: PagingLibrary {

    static let seerrPageSize = 20

    let category: SeerrDiscoverCategory
    let parent: TitledLibraryParent

    init(category: SeerrDiscoverCategory) {
        self.category = category
        self.parent = .init(
            displayTitle: category.displayTitle,
            id: "seerr-discover-\(category.rawValue)"
        )
    }

    func retrievePage(
        environment: Empty,
        pageState: LibraryPageState
    ) async throws -> [SeerrMedia] {
        guard let client = Container.shared.seerrService().client else {
            throw SeerrError.notConfigured
        }

        let pageSize = Self.seerrPageSize
        // Round up so a page with a few duplicate (dropped) results never refetches itself.
        var page = (pageState.pageOffset + pageSize - 1) / pageSize + 1
        var results: [SeerrMedia] = []

        while results.count < pageState.pageSize {
            let response = try await category.fetch(client: client, page: page)
            results.append(contentsOf: response.results)

            guard page < response.totalPages, response.results.isNotEmpty else { break }

            page += 1
        }

        return results
    }
}
