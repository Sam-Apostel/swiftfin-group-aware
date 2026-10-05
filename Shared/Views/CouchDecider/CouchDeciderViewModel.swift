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
import JellyfinAPI

/// The "What should we watch?" decider: one shuffled deck of the couch's candidates.
///
/// The view model owns the deck and does one thing per user action. All animation
/// state lives in the view, which keys its reel and flip animations on `cardGeneration`.
@MainActor
@Stateful
final class CouchDeciderViewModel: ViewModel {

    @CasePathable
    enum Action {
        case load
        case shuffle
        case notTonight
        case setFilters(CouchDeciderFilters)
        case resetExclusions
        case watch

        var transition: Transition {
            switch self {
            case .load:
                .to(.loading, then: .content)
            case .shuffle, .notTonight, .setFilters, .resetExclusions:
                .none
            case .watch:
                .background(.resolving)
            }
        }
    }

    enum BackgroundState {
        case resolving
    }

    enum Event {
        case play(BaseItemDto)
        case failed(String)
    }

    enum State {
        case content
        case error
        case initial
        case loading
    }

    let couch: CouchGroup

    @Published
    private(set) var pool: CouchDeciderPool = .empty
    @Published
    private(set) var current: CouchDeciderCandidate?
    @Published
    private(set) var filters: CouchDeciderFilters = CouchDeciderFilters()
    @Published
    private(set) var genreChips: [String] = []
    @Published
    private(set) var matchingCount: Int = 0
    @Published
    private(set) var excludedCount: Int = 0
    @Published
    private(set) var didWrap: Bool = false
    /// Bumped on every card change; the view keys its flip/reel animations on it.
    @Published
    private(set) var cardGeneration: Int = 0

    private let exclusions: CouchDeciderExclusions
    private var deck = CouchDeciderDeck(candidates: [], seed: 0)
    private var isResolvingPlayback = false

    private var excludedIDs: Set<String> {
        exclusions.excluded(couchID: couch.id)
    }

    init(couch: CouchGroup) {
        self.couch = couch
        self.exclusions = Container.shared.couchDeciderExclusions()

        super.init()
    }

    // MARK: - Lookup

    func item(for candidateID: String) -> BaseItemDto? {
        pool.items[candidateID]
    }

    /// Current card + the next `count - 1` matches (used by phone voting).
    func upcomingCandidates(_ count: Int) -> [CouchDeciderCandidate] {
        guard count > 0 else { return [] }

        return deck.upcoming(count)
    }

    // MARK: - Load

    @Function(\Action.Cases.load)
    private func _load() async throws {
        let session = try requireUserSession()
        let newPool = try await CouchDeciderCandidateSource.load(couch: couch, primary: session)

        pool = newPool
        deck = CouchDeciderDeck(
            candidates: newPool.candidates,
            seed: UInt64.random(in: UInt64.min ... UInt64.max)
        )
        deck.apply(filters: filters, excluded: excludedIDs)

        publishDeck(didWrap: false, forceNewCard: true)
    }

    // MARK: - Shuffle

    @Function(\Action.Cases.shuffle)
    private func _shuffle() {
        deck.advance()

        publishDeck(didWrap: deck.didWrap, forceNewCard: true)
    }

    // MARK: - Not Tonight

    @Function(\Action.Cases.notTonight)
    private func _notTonight() {
        guard let currentID = deck.current?.id else { return }

        exclusions.exclude(itemID: currentID, couchID: couch.id)

        // With other matches left, advance first so the next card follows the deck order
        // (and a new lap reshuffles), then drop the excluded one.
        var wrapped = false

        if deck.matchingCount > 1 {
            deck.advance()
            wrapped = deck.didWrap
        }

        deck.apply(filters: filters, excluded: excludedIDs)

        publishDeck(didWrap: wrapped && deck.current != nil, forceNewCard: true)
    }

    // MARK: - Filters

    @Function(\Action.Cases.setFilters)
    private func _setFilters(_ newFilters: CouchDeciderFilters) {
        filters = newFilters
        deck.apply(filters: newFilters, excluded: excludedIDs)

        publishDeck(didWrap: false, forceNewCard: false)
    }

    // MARK: - Reset Exclusions

    @Function(\Action.Cases.resetExclusions)
    private func _resetExclusions() {
        exclusions.reset(couchID: couch.id)
        deck.apply(filters: filters, excluded: excludedIDs)

        publishDeck(didWrap: false, forceNewCard: false)
    }

    // MARK: - Watch

    /// Resolves what to play for the current card (a series plays its next-up episode).
    ///
    /// Errors are sent as `.failed`: with `State.error`, a thrown error would blank the screen.
    @Function(\Action.Cases.watch)
    private func _watch() async {
        guard !isResolvingPlayback,
              let candidateID = deck.current?.id,
              let item = pool.items[candidateID]
        else { return }

        isResolvingPlayback = true
        defer { isResolvingPlayback = false }

        do {
            let session = try requireUserSession()
            let playbackItem = try await CouchDeciderPlayback.playbackItem(for: item, session: session)

            events.send(.play(playbackItem))
        } catch is CancellationError {
            return
        } catch {
            logger.error("Couch decider could not resolve playback: \(error.localizedDescription)")
            events.send(.failed(error.localizedDescription))
        }
    }

    // MARK: - Publish

    private func publishDeck(didWrap: Bool, forceNewCard: Bool) {
        let previousID = current?.id
        let excluded = excludedIDs

        current = deck.current
        matchingCount = deck.matchingCount
        self.didWrap = didWrap
        genreChips = CouchDeciderFilters.genreChips(
            for: pool.candidates,
            filters: filters,
            excluded: excluded
        )
        excludedCount = pool.candidates.count(where: { excluded.contains($0.id) })

        if forceNewCard || current?.id != previousID {
            cardGeneration &+= 1
        }
    }
}
