//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// The decider's filters: length, movies or shows, and genres.
///
/// Foundation only, so the rules can be tested without the Jellyfin SDK.
struct CouchDeciderFilters: Hashable, Sendable {

    /// How long a candidate may run.
    enum Length: String, CaseIterable, Hashable, Sendable {

        case any
        case underOneHour
        case underOneHourFortyFive
        case underTwoHoursThirty

        /// The longest runtime that passes, in seconds. `nil` lets everything through.
        var maxRuntime: TimeInterval? {
            switch self {
            case .any:
                nil
            case .underOneHour:
                3600
            case .underOneHourFortyFive:
                6300
            case .underTwoHoursThirty:
                9000
            }
        }
    }

    enum KindFilter: String, CaseIterable, Hashable, Sendable {

        case all

        /// Movies and standalone videos.
        case movies

        /// Shows and episodes.
        case shows
    }

    var length: Length = .any
    var kind: KindFilter = .all

    /// Selected genres. A candidate passes with any one of them, matched case-insensitively.
    var genres: Set<String> = []

    /// Whether nothing is filtered.
    var isDefault: Bool {
        length == .any && kind == .all && genres.isEmpty
    }

    /// Whether the candidate passes the length, kind and (unless ignored) genre filters.
    ///
    /// A candidate with an unknown runtime only passes `Length.any`.
    func matches(_ candidate: CouchDeciderCandidate, ignoringGenres: Bool = false) -> Bool {
        if let maxRuntime = length.maxRuntime {
            guard let runtime = candidate.runtime, runtime <= maxRuntime else { return false }
        }

        switch kind {
        case .all:
            break

        case .movies:
            guard candidate.kind == .movie else { return false }

        case .shows:
            guard candidate.kind == .series || candidate.kind == .episode else { return false }
        }

        guard !ignoringGenres, !genres.isEmpty else { return true }

        let selectedKeys = Set(genres.map(Self.genreKey))

        return candidate.genres.contains { selectedKeys.contains(Self.genreKey($0)) }
    }

    /// The genre chips to offer: the most common genres among the candidates that pass
    /// the kind and length filters and aren't excluded.
    ///
    /// - A genre needs at least 2 candidates, unless that leaves fewer than 3 chips:
    ///   then 1 candidate is enough.
    /// - Sorted by count (descending), then by name. A genre is shown in the casing it was first seen in.
    /// - Selected genres are always included (after the others), even past `limit`.
    static func genreChips(
        for candidates: [CouchDeciderCandidate],
        filters: CouchDeciderFilters,
        excluded: Set<String>,
        limit: Int = 8
    ) -> [String] {
        var counts: [String: Int] = [:]
        var displayNames: [String: String] = [:]

        for candidate in candidates {
            guard !excluded.contains(candidate.id),
                  filters.matches(candidate, ignoringGenres: true)
            else { continue }

            var seenKeys: Set<String> = []

            for genre in candidate.genres {
                let key = genreKey(genre)

                guard !key.isEmpty, seenKeys.insert(key).inserted else { continue }

                counts[key, default: 0] += 1

                if displayNames[key] == nil {
                    displayNames[key] = genre.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }

        let sortedKeys = counts.keys.sorted { lhs, rhs in
            let lhsCount = counts[lhs] ?? 0
            let rhsCount = counts[rhs] ?? 0

            if lhsCount != rhsCount {
                return lhsCount > rhsCount
            }

            let lhsName = displayNames[lhs] ?? lhs
            let rhsName = displayNames[rhs] ?? rhs
            let order = lhsName.localizedStandardCompare(rhsName)

            if order != .orderedSame {
                return order == .orderedAscending
            }

            return lhs < rhs
        }

        var chosenKeys = sortedKeys.filter { (counts[$0] ?? 0) >= 2 }

        if min(chosenKeys.count, max(limit, 0)) < 3 {
            chosenKeys = sortedKeys
        }

        var chips: [String] = []
        var chipKeys: Set<String> = []

        for key in chosenKeys.prefix(max(limit, 0)) {
            chips.append(displayNames[key] ?? key)
            chipKeys.insert(key)
        }

        let missingSelected = filters.genres
            .filter { chipKeys.insert(genreKey($0)).inserted }
            .map { displayNames[genreKey($0)] ?? $0 }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }

        return chips + missingSelected
    }

    /// The case-insensitive key of a genre.
    private static func genreKey(_ genre: String) -> String {
        genre.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
