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

    /// Family movies rated PG or lower (kid-safe).
    case family
    /// Animated movies rated PG or lower (kid-safe).
    case animatedMovies
    /// Family shows rated TV-PG or lower (kid-safe).
    case familyTV
    case trending
    case popularMovies
    case popularTV
    case upcomingMovies
    case upcomingTV

    /// The only rows shown in kid mode, i.e. while a child is on the couch (#49).
    static let kidSafeRows: [SeerrDiscoverCategory] = [
        .family,
        .animatedMovies,
        .familyTV,
    ]

    /// The rows shown when no child is on the couch, in the iOS order (#13).
    static let grownUpRows: [SeerrDiscoverCategory] = [
        .trending,
        .popularMovies,
        .popularTV,
        .upcomingMovies,
        .upcomingTV,
    ]

    /// The Discover rows for a couch: only `kidSafeRows` in kid mode.
    static func rows(isKidMode: Bool) -> [SeerrDiscoverCategory] {
        isKidMode ? kidSafeRows : grownUpRows
    }

    var displayTitle: String {
        switch self {
        case .family:
            L10n.SeerrDiscover.familyMovieNight
        case .animatedMovies:
            L10n.SeerrDiscover.animatedMovies
        case .familyTV:
            L10n.SeerrDiscover.familyShows
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
        case .animatedMovies:
            "sparkles"
        case .familyTV:
            "tv.fill"
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
        case .animatedMovies:
            try await client.animatedMovies(page: page)
        case .familyTV:
            try await client.familyTV(page: page)
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
