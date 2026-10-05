//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// Where everyone on the couch is in one item, and whether Play should ask
/// whose resume point to start from.
///
/// Positions within about 2 minutes of each other count as the same point.
/// Members who finished the item (`isPlayed`) count as finished, not as "at 0",
/// and positions in the first 2 minutes count as not started.
///
/// Play asks when someone is at a point the primary user isn't at, including
/// someone who hasn't started while the primary user is partway through. When
/// every position agrees, Play stays one tap.
struct CouchResumePlan: Equatable {

    /// One person's own user data for the item.
    struct Member: Equatable {
        let name: String
        let positionTicks: Int
        let isPlayed: Bool
        let isPrimary: Bool

        init(name: String, positionTicks: Int?, isPlayed: Bool?, isPrimary: Bool) {
            self.name = name
            self.positionTicks = positionTicks ?? 0
            self.isPlayed = isPlayed ?? false
            self.isPrimary = isPrimary
        }
    }

    /// A position one or more members share.
    struct Point: Equatable, Identifiable {
        /// Where to start: the primary user's position when they share this point,
        /// otherwise the earliest position, so nobody misses anything.
        let ticks: Int
        /// Member names, in couch order.
        let names: [String]
        let includesPrimary: Bool

        var id: Int {
            ticks
        }

        /// "1:10:05"
        var timecode: String {
            CouchResumePlan.timecode(ticks)
        }
    }

    static let ticksPerSecond = 10_000_000

    /// Positions closer together than this count as the same point.
    static let toleranceTicks = 120 * ticksPerSecond

    /// The item these positions are for.
    let itemID: String

    /// Every distinct resume point, furthest first.
    let points: [Point]

    /// The other members who haven't started (and haven't finished), in couch order.
    let notStartedNames: [String]

    init(itemID: String, members: [Member]) {
        self.itemID = itemID
        self.points = Self.points(for: members)
        self.notStartedNames = members
            .filter { !$0.isPrimary && !$0.isPlayed && $0.positionTicks <= Self.toleranceTicks }
            .map(\.name)
    }

    /// Whether Play should ask whose resume point to start from: someone is at a point
    /// the primary user isn't at, or the primary user is partway through while someone
    /// else hasn't started, so Play would silently skip ahead for them.
    var needsChoice: Bool {
        if points.contains(where: { !$0.includesPrimary }) {
            return true
        }

        return points.contains(where: \.includesPrimary) && !notStartedNames.isEmpty
    }

    /// The furthest point the primary user isn't at, for "Sam is at 1:10:05".
    /// When the only difference is members who haven't started: a point at 0 with them.
    var hint: Point? {
        if let point = points.first(where: { !$0.includesPrimary }) {
            return point
        }

        guard needsChoice else { return nil }

        return Point(ticks: 0, names: notStartedNames, includesPrimary: false)
    }

    // MARK: - Clustering

    private static func points(for members: [Member]) -> [Point] {
        let order = Dictionary(
            members.enumerated().map { ($0.element.name, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )

        let started = members
            .filter { !$0.isPlayed && $0.positionTicks > toleranceTicks }
            .sorted { $0.positionTicks > $1.positionTicks }

        var clusters: [[Member]] = []

        for member in started {
            if let anchor = clusters.last?.first,
               anchor.positionTicks - member.positionTicks <= toleranceTicks
            {
                clusters[clusters.count - 1].append(member)
            } else {
                clusters.append([member])
            }
        }

        return clusters.map { cluster in
            let primary = cluster.first(where: \.isPrimary)
            let earliest = cluster.map(\.positionTicks).min() ?? 0
            let names = cluster
                .sorted { (order[$0.name] ?? 0) < (order[$1.name] ?? 0) }
                .map(\.name)

            return Point(
                ticks: primary?.positionTicks ?? earliest,
                names: names,
                includesPrimary: primary != nil
            )
        }
    }

    // MARK: - Formatting

    /// "1:10:05" or "42:10"
    static func timecode(_ ticks: Int) -> String {
        let totalSeconds = max(0, ticks / ticksPerSecond)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%d:%02d", minutes, seconds)
    }
}
