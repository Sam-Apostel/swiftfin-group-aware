//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import Foundation

/// The tvOS Discover screen, rendered by `ContentGroupView` like Home:
///
/// 1. a cinematic hero of Trending (Family movie night when a kid is on the couch),
/// 2. Search and Seerr settings shortcuts,
/// 3. poster rows for the other categories, each with a paged "see all" grid.
///
/// The hero fetch is the only `try`: when Seerr can't be reached, `ContentGroupView`
/// shows the error with Retry. The rows load lazily through their own view models.
struct SeerrDiscoverContentGroupProvider: ContentGroupProvider {

    let id: String = "seerr-discover"

    var displayTitle: String {
        L10n.SeerrDiscover.title
    }

    /// The iOS row order (#13).
    private static let rowCategories: [SeerrDiscoverCategory] = [
        .trending,
        .popularMovies,
        .popularTV,
        .upcomingMovies,
        .upcomingTV,
    ]

    func makeGroups(environment: Empty) async throws -> [any ContentGroup] {
        guard let client = Container.shared.seerrService().client else {
            throw SeerrError.notConfigured
        }

        let members = Container.shared.currentUserSession()?.couch.members ?? []
        let isKidOnCouch = members.contains(where: \.isKid)
        let isKidsOnlyCouch = members.isNotEmpty && members.allSatisfy(\.isKid)

        // With a kid on the couch, the biggest image on screen should be a family pick
        let heroCategory: SeerrDiscoverCategory = isKidOnCouch ? .family : .trending
        let heroPage = try await heroCategory.fetch(client: client, page: 1)
        let heroItems = Self.uniqued(heroPage.results)

        var groups: [any ContentGroup] = []

        if heroItems.isNotEmpty {
            groups.append(SeerrCinematicContentGroup(items: heroItems))
        }

        let shortcuts: [SeerrDiscoverShortcut] = isKidsOnlyCouch ? [.settings] : [.search, .settings]

        groups.append(
            PillGroup(
                displayTitle: "",
                id: "seerr-shortcuts",
                elements: shortcuts
            ) { router, shortcut in
                switch shortcut {
                case .search:
                    router.route(to: .seerrSearch)
                case .settings:
                    router.route(to: .seerrSettings)
                }
            }
        )

        if isKidsOnlyCouch {
            // The hero already shows the first page of family picks
            groups.append(
                PosterGroup(
                    id: "seerr-row-family-more",
                    library: SeerrDiscoverMoreLibrary(category: .family, skippingPages: 1),
                    posterDisplayType: .portrait,
                    posterSize: .small
                )
            )
        } else {
            for category in Self.rowCategories where category != heroCategory {
                groups.append(
                    PosterGroup(
                        id: "seerr-row-\(category.rawValue)",
                        library: SeerrDiscoverLibrary(category: category),
                        posterDisplayType: .portrait,
                        posterSize: .small
                    )
                )
            }
        }

        return groups
    }

    /// Posters are keyed by `id` (the TMDB id), so drop repeated ids.
    private static func uniqued(_ items: [SeerrMedia]) -> [SeerrMedia] {
        var seen = Set<Int>()
        return items.filter { seen.insert($0.id).inserted }
    }
}

// MARK: - SeerrDiscoverMoreLibrary

/// A Discover category without its first page(s), for a row below a hero that already shows them.
///
/// Pages through `SeerrDiscoverLibrary`, shifted by `skippingPages` Seerr pages.
struct SeerrDiscoverMoreLibrary: PagingLibrary {

    let category: SeerrDiscoverCategory
    let parent: TitledLibraryParent
    let skippingPages: Int

    init(category: SeerrDiscoverCategory, skippingPages: Int) {
        self.category = category
        self.skippingPages = max(skippingPages, 0)
        self.parent = .init(
            displayTitle: category.displayTitle,
            id: "seerr-discover-\(category.rawValue)-more"
        )
    }

    func retrievePage(
        environment: Empty,
        pageState: LibraryPageState
    ) async throws -> [SeerrMedia] {
        let shiftedPageState = LibraryPageState(
            pageOffset: pageState.pageOffset + skippingPages * SeerrDiscoverLibrary.seerrPageSize,
            pageSize: pageState.pageSize,
            userSession: pageState.userSession
        )

        return try await SeerrDiscoverLibrary(category: category)
            .retrievePage(environment: environment, pageState: shiftedPageState)
    }
}
