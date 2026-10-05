//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// A small seeded random number generator (SplitMix64).
///
/// The same seed always gives the same numbers, on every device and in every process,
/// so the deck order is reproducible in tests.
struct CouchDeciderRandom: RandomNumberGenerator, Sendable {

    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15

        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB

        return z ^ (z >> 31)
    }

    /// A uniform random number in (0, 1].
    mutating func nextUnitInterval() -> Double {
        // 53 random bits, shifted from [0, 2^53) to (0, 2^53].
        Double((next() >> 11) + 1) * 0x1p-53
    }
}

/// The shuffled deck of candidates the decider shows one card at a time.
///
/// - The order is a weighted shuffle: candidates with heavier sources (picks, then next up,
///   then new) tend to come first, but every candidate can come first.
/// - Filters and exclusions hide cards without changing the order.
/// - At the end of the deck a new lap starts with a fresh shuffle.
///
/// Foundation only, so the rules can be tested without the Jellyfin SDK.
struct CouchDeciderDeck: Sendable {

    /// The card on screen, or `nil` when no candidate matches.
    private(set) var current: CouchDeciderCandidate?

    /// How many candidates match the filters and aren't excluded.
    private(set) var matchingCount: Int

    /// Whether the last `advance()` started a new lap. `false` after every other call.
    private(set) var didWrap: Bool

    /// The weight used for a candidate without any source, so it still gets a place (late) in the deck.
    private static let minimumWeight = 0.01

    private let candidates: [CouchDeciderCandidate]
    private let seed: UInt64

    /// The current lap's order of every candidate, matching or not.
    private var order: [CouchDeciderCandidate]

    /// The index in `order` of `current`, or of the last card shown when nothing matches.
    private var position: Int
    private var lap: UInt64

    private var filters: CouchDeciderFilters
    private var excluded: Set<String>

    /// Creates a deck with no filters and no exclusions, showing its first card.
    ///
    /// - Parameters:
    ///   - candidates: The candidates. Duplicate ids are dropped (the first one is kept).
    ///   - seed: The shuffle seed. Pass `UInt64.random(in: .min ... .max)` for a new order each time.
    init(candidates: [CouchDeciderCandidate], seed: UInt64) {
        var seenIDs: Set<String> = []
        let uniqueCandidates = candidates.filter { seenIDs.insert($0.id).inserted }

        self.candidates = uniqueCandidates
        self.seed = seed
        self.order = Self.weightedOrder(uniqueCandidates, seed: seed)
        self.position = 0
        self.lap = 0
        self.filters = CouchDeciderFilters()
        self.excluded = []
        self.current = nil
        self.matchingCount = 0
        self.didWrap = false

        apply(filters: CouchDeciderFilters(), excluded: [])
    }

    // MARK: - Actions

    /// Applies new filters and exclusions.
    ///
    /// The current card stays when it still matches. Otherwise the deck moves on to the
    /// next matching card in the order (from the top of the deck when there is none further down).
    mutating func apply(filters: CouchDeciderFilters, excluded: Set<String>) {
        self.filters = filters
        self.excluded = excluded
        didWrap = false
        matchingCount = order.reduce(0) { count, candidate in
            matches(candidate) ? count + 1 : count
        }

        if let current, matches(current) {
            return
        }

        let start = current == nil ? position : position + 1

        if let index = firstMatch(from: start) ?? firstMatch(in: 0 ..< min(max(start, 0), order.count)) {
            position = index
            current = order[index]
        } else {
            current = nil
        }
    }

    /// Shows the next matching card.
    ///
    /// At the end of the deck, this starts a new lap with a fresh shuffle and sets `didWrap`.
    /// With at least 2 matching cards, the same card never shows twice in a row.
    mutating func advance() {
        didWrap = false

        guard matchingCount > 0 else {
            current = nil
            return
        }

        let start = current == nil ? position : position + 1

        if let index = firstMatch(from: start) {
            position = index
            current = order[index]
            return
        }

        let previousID = current?.id

        lap &+= 1
        order = Self.weightedOrder(candidates, seed: seed &+ lap)
        didWrap = true

        guard var index = firstMatch(from: 0) else {
            position = 0
            current = nil
            return
        }

        if matchingCount >= 2, order[index].id == previousID,
           let nextIndex = firstMatch(from: index + 1)
        {
            // Move the card that was just on screen behind the next matching card.
            let repeated = order.remove(at: index)
            order.insert(repeated, at: nextIndex)
            index = firstMatch(from: 0) ?? index
        }

        position = index
        current = order[index]
    }

    /// Shows this candidate (e.g. the title an Undo just brought back), keeping the lap's order.
    ///
    /// - Returns: `false`, without changing anything, when the candidate isn't in the deck
    ///   or doesn't match the filters and exclusions.
    @discardableResult
    mutating func show(candidateID: String) -> Bool {
        guard let index = order.firstIndex(where: { $0.id == candidateID }),
              matches(order[index])
        else { return false }

        didWrap = false
        position = index
        current = order[index]

        return true
    }

    /// The current card followed by the next `count - 1` matching cards of this lap.
    ///
    /// Doesn't wrap into a new lap, so it can return fewer than `count` cards.
    func upcoming(_ count: Int) -> [CouchDeciderCandidate] {
        guard count > 0, let current else { return [] }

        var result = [current]
        var index = position + 1

        while result.count < count, index < order.count {
            if matches(order[index]) {
                result.append(order[index])
            }

            index += 1
        }

        return result
    }

    // MARK: - Shuffle

    /// A weighted random order (Efraimidis–Spirakis): each candidate gets the key
    /// `pow(u, 1 / weight)`, with `u` uniform in (0, 1], and the keys are sorted descending.
    ///
    /// A candidate comes first with a probability proportional to its weight.
    /// Ties are broken by id, so the same seed always gives the same order.
    static func weightedOrder(_ candidates: [CouchDeciderCandidate], seed: UInt64) -> [CouchDeciderCandidate] {
        var random = CouchDeciderRandom(seed: seed)

        let keyed: [(key: Double, candidate: CouchDeciderCandidate)] = candidates.map { candidate in
            let u = random.nextUnitInterval()
            let weight = candidate.weight > 0 ? candidate.weight : minimumWeight

            return (key: pow(u, 1 / weight), candidate: candidate)
        }

        return keyed
            .sorted { lhs, rhs in
                if lhs.key != rhs.key {
                    return lhs.key > rhs.key
                }

                return lhs.candidate.id < rhs.candidate.id
            }
            .map(\.candidate)
    }

    // MARK: - Helpers

    private func matches(_ candidate: CouchDeciderCandidate) -> Bool {
        !excluded.contains(candidate.id) && filters.matches(candidate)
    }

    private func firstMatch(from start: Int) -> Int? {
        firstMatch(in: min(max(start, 0), order.count) ..< order.count)
    }

    private func firstMatch(in range: Range<Int>) -> Int? {
        guard !range.isEmpty else { return nil }

        return range.first { matches(order[$0]) }
    }
}
