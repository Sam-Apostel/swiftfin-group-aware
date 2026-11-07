//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// A stretch of a universe's timeline: an era, a decade, a year, or one creator's lane.
struct UniverseSection: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String?
    let entries: [UniverseEntry]
}

/// Turns a universe into sections for one timeline. Pure, so it's cheap to redo on every toggle.
enum UniverseLayout {

    static func defaultTimeline(for universe: Universe) -> UniverseTimeline {
        let available = universe.availableTimelines
        switch universe.kind {
        case .playlist where available.contains(.chronological):
            return .chronological
        case .nonFiction where available.contains(.historical):
            return .historical
        case .creatorCollab where available.contains(.lanes):
            return .lanes
        default:
            if available.contains(.chronological), universe.orderSource == "llm" || universe.orderSource == "curated" {
                return .chronological
            }
            return .release
        }
    }

    static func title(for timeline: UniverseTimeline, in universe: Universe) -> String {
        switch timeline {
        case .release:
            L10n.Universes.timelineRelease
        case .chronological:
            switch universe.orderSource {
            case "series": L10n.Universes.timelineSeries
            case "playlist": L10n.Universes.timelinePlaylist
            default: L10n.Universes.timelineStory
            }
        case .historical:
            L10n.Universes.timelineHistory
        case .lanes:
            L10n.Universes.timelineLanes
        }
    }

    /// Entries in the order a timeline plays them, leaving out what doesn't sit on it.
    static func ordered(_ universe: Universe, timeline: UniverseTimeline) -> [UniverseEntry] {
        switch timeline {
        case .release, .lanes:
            return universe.entries.sorted(by: releaseOrder)
        case .chronological:
            let placed = universe.entries.filter { $0.positions.chronological != nil }
            return placed.sorted { ($0.positions.chronological ?? 0, releaseKey($0)) < ($1.positions.chronological ?? 0, releaseKey($1)) }
        case .historical:
            let placed = universe.entries.filter { $0.positions.historical != nil }
            return placed.sorted {
                ($0.positions.historical?.start ?? 0, $0.positions.historical?.end ?? 0) < ($1.positions.historical?.start ?? 0, $1.positions.historical?.end ?? 0)
            }
        }
    }

    static func sections(for universe: Universe, timeline: UniverseTimeline, onlyLibrary: Bool) -> [UniverseSection] {
        let entries = ordered(universe, timeline: timeline).filter { !onlyLibrary || $0.inLibrary }
        guard entries.isNotEmpty else { return [] }

        switch timeline {
        case .release:
            return releaseSections(entries, eras: universe.kind == .nonFiction ? nil : universe.theme.eras)
        case .chronological:
            return [UniverseSection(id: "order", title: title(for: timeline, in: universe), subtitle: nil, entries: entries)]
        case .historical:
            return historySections(entries, eras: universe.theme.eras)
        case .lanes:
            return laneSections(entries)
        }
    }

    // MARK: - Release

    private static func releaseKey(_ entry: UniverseEntry) -> Int {
        entry.positions.release ?? Int.max
    }

    private static func releaseOrder(_ lhs: UniverseEntry, _ rhs: UniverseEntry) -> Bool {
        releaseKey(lhs) == releaseKey(rhs) ? lhs.title < rhs.title : releaseKey(lhs) < releaseKey(rhs)
    }

    private static func releaseSections(_ entries: [UniverseEntry], eras: [UniverseTheme.Era]?) -> [UniverseSection] {
        let years = entries.compactMap(\.year)
        let span = (years.max() ?? 0) - (years.min() ?? 0)

        return group(entries) { entry -> (id: String, title: String, subtitle: String?) in
            guard let year = entry.year else {
                return ("undated", L10n.Universes.unknownDate, nil)
            }
            if let era = eras?.first(where: { year >= $0.start && year < $0.end }) {
                return ("era-\(era.id)", era.label, L10n.Universes.span(from: era.start, to: era.end - 1))
            }
            if span <= 12 {
                return ("year-\(year)", String(year), nil)
            }
            let decade = year - ((year % 10) + 10) % 10
            return ("decade-\(decade)", "\(decade)s", nil)
        }
    }

    // MARK: - History

    private static func historySections(_ entries: [UniverseEntry], eras: [UniverseTheme.Era]?) -> [UniverseSection] {
        group(entries) { entry -> (id: String, title: String, subtitle: String?) in
            guard let start = entry.positions.historical?.start else {
                return ("undated", L10n.Universes.undated, nil)
            }
            if let era = eras?.first(where: { start >= $0.start && start < $0.end }) {
                return ("era-\(era.id)", era.label, L10n.Universes.span(from: era.start, to: min(era.end, Calendar.current.component(.year, from: .now))))
            }
            let century = start >= 0 ? start / 100 : -((-start + 99) / 100)
            let from = century * 100
            return ("century-\(century)", L10n.Universes.span(from: from, to: from + 99), nil)
        }
    }

    // MARK: - Lanes

    private static func laneSections(_ entries: [UniverseEntry]) -> [UniverseSection] {
        var lanes: [String: [UniverseEntry]] = [:]
        var order: [String] = []
        for entry in entries {
            let lane = entry.lane ?? ""
            if lanes[lane] == nil {
                order.append(lane)
            }
            lanes[lane, default: []].append(entry)
        }
        // Busiest lanes first; entries without a lane last.
        return order
            .sorted { lhs, rhs in
                if lhs.isEmpty != rhs.isEmpty { return !lhs.isEmpty }
                return (lanes[lhs]?.count ?? 0) > (lanes[rhs]?.count ?? 0)
            }
            .map { lane in
                UniverseSection(
                    id: "lane-\(lane)",
                    title: lane.isEmpty ? L10n.Universes.kindVideo : lane,
                    subtitle: nil,
                    entries: lanes[lane] ?? []
                )
            }
    }

    // MARK: - Grouping

    /// Groups consecutive entries with the same key, keeping their order.
    private static func group(
        _ entries: [UniverseEntry],
        key: (UniverseEntry) -> (id: String, title: String, subtitle: String?)
    ) -> [UniverseSection] {
        var sections: [UniverseSection] = []
        var current: (id: String, title: String, subtitle: String?)?
        var bucket: [UniverseEntry] = []
        var used: [String: Int] = [:]

        func flush() {
            guard let current, bucket.isNotEmpty else { return }
            let count = used[current.id, default: 0]
            used[current.id] = count + 1
            sections.append(UniverseSection(
                id: count == 0 ? current.id : "\(current.id)-\(count)",
                title: current.title,
                subtitle: current.subtitle,
                entries: bucket
            ))
        }

        for entry in entries {
            let entryKey = key(entry)
            if entryKey.id != current?.id {
                flush()
                current = entryKey
                bucket = []
            }
            bucket.append(entry)
        }
        flush()
        return sections
    }
}
