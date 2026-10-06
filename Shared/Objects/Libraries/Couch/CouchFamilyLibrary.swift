//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

/// "Family movie night": well-rated family films that everyone on the couch can watch,
/// for a couch with a kid and grown-ups (`CouchHomeSupport.hasKidAndAdults(_:)`).
///
/// - The family genres are resolved from `/Genres` by keyword ("Family", "Familie", "Famille"),
///   because Jellyfin matches genre names as they are in the metadata, which can be Dutch or French.
///   Broad genres such as Adventure are never added.
/// - The best-rated family movies (community rating) are filtered with every member's own account,
///   failing closed for restricted members (`CouchItemFilter.filter(_:couch:primary:excludePlayedBy:)`),
///   then toddler content is removed (`CouchHomeSupport.removingToddlerContent`).
/// - A kid without an age limit on the server only gets titles rated kid-safe (`KidRatings`), as in the decider.
/// - The top `shuffledCount` are shuffled with a seed that changes once a day, and `shownCount` are shown.
struct CouchFamilyLibrary: BaseItemKindLibrary {

    /// Lowercased genre name keywords of family content, matched as substrings
    /// (English, Dutch and German, French).
    static let familyGenreKeywords = ["family", "familie", "famille"]

    /// How many family movies are requested, best rated first, before the couch filters.
    static let candidateCount = 80

    /// How many of the best-rated remaining movies take part in the daily shuffle.
    static let shuffledCount = 40

    /// How many movies the row shows.
    static let shownCount = 20

    let couch: CouchGroup
    let libraryItemTypes: [BaseItemKind] = [.movie]
    let parent: TitledLibraryParent = .init(
        displayTitle: L10n.CouchHome.familyMovieNight,
        id: "couch-family"
    )

    func retrievePage(
        environment: Empty,
        pageState: LibraryPageState
    ) async throws -> [BaseItemDto] {
        // The whole row is the first page: don't compute it again for an empty second page
        guard pageState.pageOffset < Self.shownCount else { return [] }
        guard CouchHomeSupport.hasKidAndAdults(couch) else { return [] }

        let primary = pageState.userSession
        let genreIDs = try await Self.familyGenreIDs(session: primary)

        // Without genre ids `/Items` would return every movie
        guard genreIDs.isNotEmpty else { return [] }

        var parameters = Paths.GetItemsParameters()
        parameters.enableUserData = true
        // Genres and provider ids: the toddler filter doesn't have to look these items up again
        parameters.fields = PosterSubtitleField.itemFields + [.providerIDs]
        parameters.genreIDs = genreIDs
        parameters.includeItemTypes = [.movie]
        parameters.isRecursive = true
        parameters.limit = Self.candidateCount
        parameters.sortBy = [.communityRating, .sortName]
        parameters.sortOrder = [.descending, .ascending]
        parameters.userID = primary.user.id

        let request = Paths.getItems(parameters: parameters)
        let response = try await primary.client.send(request)
        let familyMovies = response.value.items ?? []

        // Fails closed: when a restricted member (a kid) couldn't be checked,
        // only what an at least as restricted member verified is kept.
        let visibleToEveryone = await CouchItemFilter.filter(
            familyMovies,
            couch: couch,
            primary: primary,
            excludePlayedBy: .allMembers
        )

        let rated = Self.keepingKidSafeRatings(visibleToEveryone, couch: couch)

        let items = await CouchHomeSupport.removingToddlerContent(
            rated,
            couch: couch,
            session: primary
        )

        let shown = Self.dailyShuffle(
            Array(items.prefix(Self.shuffledCount)),
            couch: couch,
            date: .now
        )
        .prefix(Self.shownCount)

        return CouchHomeSupport.page(Array(shown), pageState)
    }

    // MARK: - Genres

    /// The ids of the family genres, as `session` sees them.
    static func familyGenreIDs(session: UserSession) async throws -> [String] {
        var parameters = Paths.GetGenresParameters()
        parameters.enableImages = false
        parameters.includeItemTypes = [.movie]
        parameters.userID = session.user.id

        let request = Paths.getGenres(parameters: parameters)
        let response = try await session.client.send(request)

        return (response.value.items ?? [])
            .filter { genre in
                isFamilyGenre(genre.name)
            }
            .compactMap(\.id)
    }

    /// Whether a genre name is a family genre, e.g. "Family", "Familie", "Famille" or "Familiefilm".
    static func isFamilyGenre(_ name: String?) -> Bool {
        guard let name = name?.lowercased() else { return false }

        return familyGenreKeywords.contains { name.contains($0) }
    }

    // MARK: - Ratings

    /// With a kid on the couch who has no age limit on the server
    /// (`CouchDeciderCandidateSource.needsRatingCeiling(_:)`), keeps only the movies rated kid-safe
    /// (`KidRatings.isKidSafe(_:)`). Fails closed: unrated movies are left out.
    static func keepingKidSafeRatings(_ items: [BaseItemDto], couch: CouchGroup) -> [BaseItemDto] {
        guard couch.members.contains(where: { CouchDeciderCandidateSource.needsRatingCeiling($0) }) else {
            return items
        }

        return items.filter { item in
            let rating = item.customRating?.nilIfBlank ?? item.officialRating?.nilIfBlank

            return KidRatings.isKidSafe(rating)
        }
    }

    // MARK: - Daily shuffle

    /// The items in an order that stays the same all day for this couch, and changes the next day.
    static func dailyShuffle(_ items: [BaseItemDto], couch: CouchGroup, date: Date) -> [BaseItemDto] {
        let day = Int(Calendar.current.startOfDay(for: date).timeIntervalSince1970 / 86400)
        var random = CouchDeciderRandom(seed: stableHash(couch.id) ^ UInt64(truncatingIfNeeded: day))

        return items.shuffled(using: &random)
    }

    /// FNV-1a: the same value on every launch (`String.hashValue` is seeded per process).
    private static func stableHash(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325

        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }

        return hash
    }
}
