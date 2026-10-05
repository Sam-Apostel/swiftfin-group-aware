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

@MainActor
@Stateful
final class ContentGroupViewModel<Provider: ContentGroupProvider>: ViewModel {

    @CasePathable
    enum Action {
        case refresh

        var transition: Transition {
            .to(.refreshing, then: .content)
                .whenBackground(.refreshing)
        }
    }

    enum BackgroundState {
        case refreshing
    }

    enum State {
        case content
        case error
        case initial
        case refreshing
    }

    @Published
    private(set) var groups: [any ContentGroup] = []

    private var candidateGroups: [any ContentGroup] = []
    private var lastRefreshDate = Date.distantPast
    private var lastRefreshSignalDate = Date.distantPast

    /// The ids of the watchlist picks for the couch (`provider.picksCouch`, `CouchHomeSupport.pickEntries(for:)`)
    /// when the groups were last refreshed. `nil` until the first refresh, or when the provider has no couch.
    private var refreshedCouchPickIDs: Set<String>?
    /// The ids of the arrivals the couch's members see ("Just arrived") when the groups were last refreshed.
    /// `nil` until the first refresh, or when the provider has no couch.
    private var refreshedArrivalIDs: Set<String>?
    /// Asks for one more picks and arrivals comparison, e.g. after a refresh ended.
    private let couchPicksCheck = PassthroughSubject<Void, Never>()
    /// The refresh of the "Just arrived" rows after the arrivals changed.
    private var arrivalsRefreshTask: Task<Void, Never>?

    /// Whether a full refresh is showing the groups as they load (`provider.revealsProgressively`).
    private var isRevealing = false

    private var hasPendingRefreshSignals: Bool {
        lastRefreshSignalDate > lastRefreshDate
    }

    var provider: Provider

    init(provider: Provider) {
        self.provider = provider
        super.init()

        Publishers.Merge(
            Notifications[.itemUserDataDidChange].publisher.map { _ in () },
            Notifications[.itemMetadataDidChange].publisher.map { _ in () }
        )
        .sink { [weak self] _ in
            self?.lastRefreshSignalDate = Date.now
        }
        .store(in: &cancellables)

        if provider.picksCouch != nil {
            observeCouchPicks()
            observeArrivals()
        }
    }

    func refreshIfNeeded(
        sinceLastDisappear interval: TimeInterval,
        staleThreshold: TimeInterval = 60
    ) {
        guard interval > staleThreshold || hasPendingRefreshSignals else { return }

        background.refresh()
    }

    func refreshIfPendingChanges() {
        guard hasPendingRefreshSignals else { return }

        refresh()
    }

    @Function(\Action.Cases.refresh)
    private func _refresh() async throws {
        // The full refresh that is revealing the groups loads every one of them already,
        // and showing all of them now could put a group above a visible one.
        if StateTask.isBackground, isRevealing {
            return
        }

        // Read before the rows fetch: picks or arrivals that change while they fetch trigger one more refresh
        refreshedCouchPickIDs = currentCouchPickIDs()
        refreshedArrivalIDs = currentArrivalIDs()

        if StateTask.isBackground {
            try await backgroundRefresh()
        } else {
            try await fullRefresh()
        }

        lastRefreshDate = Date.now
        couchPicksCheck.send()
    }

    private func getViewModel(for group: some ContentGroup) -> any WithRefresh {
        group.viewModel
    }

    private func resolveGroups() {
        groups = candidateGroups
            .filter(\._shouldBeResolved)
    }

    private func refreshViewModels(
        for groups: [any ContentGroup],
        inBackground: Bool
    ) async throws {
        let viewModels = groups.map { getViewModel(for: $0) }
            .uniqued { ObjectIdentifier($0 as AnyObject) }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for viewModel in viewModels {
                group.addTask {
                    if inBackground {
                        await viewModel.background.refresh()
                    } else {
                        await viewModel.refresh()
                    }
                }
            }

            try await group.waitForAll()
        }
    }

    private func backgroundRefresh() async throws {
        try await refreshViewModels(
            for: candidateGroups,
            inBackground: true
        )

        resolveGroups()
    }

    private func fullRefresh() async throws {

        self.groups = []
        self.candidateGroups = []

        let newGroups = try await provider.makeGroups(environment: provider.environment)

        if provider.revealsProgressively {
            candidateGroups = newGroups

            isRevealing = true
            defer { isRevealing = false }

            await revealViewModels(of: newGroups)
        } else {
            try await refreshViewModels(
                for: newGroups,
                inBackground: false
            )

            candidateGroups = newGroups
        }

        resolveGroups()
    }

    /// Refreshes the view models of `newGroups` concurrently and, each time one finishes, shows the longest
    /// prefix of `newGroups` whose view models all finished (`_shouldBeResolved` rows only).
    ///
    /// - A group is never shown above a visible group: the prefix only grows.
    /// - Empty groups count as finished, so they don't hold up the groups below them.
    /// - The view leaves the spinner as soon as the shown prefix isn't empty. On tvOS the cinematic hero
    ///   is the first group, so the first groups shown always include it (when it has anything to show)
    ///   and the first focus lands on it, not on a row that moves.
    private func revealViewModels(of newGroups: [any ContentGroup]) async {
        let viewModels = newGroups.map { getViewModel(for: $0) }

        // Groups that share a view model (the tvOS cinematic hero and its "Recently Added" row)
        // finish together: every group points at the first group with its view model.
        let objects = viewModels.map { $0 as AnyObject }
        let owners: [Int] = objects.indices.map { index in
            objects[..<index].firstIndex { $0 === objects[index] } ?? index
        }

        var finishedOwners: Set<Int> = []

        await withTaskGroup(of: Int.self) { group in
            for index in owners.indices where owners[index] == index {
                let viewModel = viewModels[index]

                group.addTask {
                    await viewModel.refresh()
                    return index
                }
            }

            for await finishedIndex in group {
                finishedOwners.insert(finishedIndex)

                let finishedCount = owners.firstIndex { !finishedOwners.contains($0) } ?? owners.count

                showFinishedPrefix(of: newGroups, count: finishedCount)
            }
        }
    }

    private func showFinishedPrefix(of newGroups: [any ContentGroup], count: Int) {
        let prefix = newGroups
            .prefix(count)
            .filter(\._shouldBeResolved)

        guard prefix.map(\.id) != groups.map(\.id) else { return }

        groups = prefix
    }
}

// MARK: - Couch picks

@MainActor
extension ContentGroupViewModel {

    /// Refreshes the household watchlist every 2 minutes while the groups are on screen, so picks
    /// tagged on another device show up (tvOS has no pull to refresh). Does nothing without `provider.picksCouch`.
    ///
    /// Run it from the view's `.task`, which cancels it when the view disappears.
    func refreshCouchPicksWhileVisible() async {
        guard provider.picksCouch != nil else { return }

        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(120))
            } catch {
                return
            }

            await refreshCouchPicksStore()
        }
    }

    /// Refreshes the household watchlist unless that happened moments ago,
    /// e.g. when the app comes back to the foreground. Does nothing without `provider.picksCouch`.
    func refreshCouchPicksIfStale() {
        guard provider.picksCouch != nil else { return }

        Task { [weak self] in
            await self?.refreshCouchPicksStore()
        }
    }

    /// The store publishes its new entries, which `observeCouchPicks` compares.
    private func refreshCouchPicksStore() async {
        let store = Container.shared.audienceWatchlistStore()

        if let lastRefreshDate = store.lastRefreshDate, Date.now.timeIntervalSince(lastRefreshDate) < 30 {
            return
        }

        await store.refreshFromCurrentSession()
    }

    /// Refreshes the groups when the picks for exactly this couch change: added, retagged or removed,
    /// on this device or (after a store refresh) on another one.
    private func observeCouchPicks() {
        let store = Container.shared.audienceWatchlistStore()

        // `$entries` emits before the value is set, the debounce also lets several changes settle
        Publishers.Merge(
            store.$entries.map { _ in () },
            couchPicksCheck
        )
        .debounce(for: 1, scheduler: RunLoop.main)
        .sink { [weak self] _ in
            self?.refreshIfCouchPicksChanged()
        }
        .store(in: &cancellables)
    }

    /// The picks for this couch, defined once for Home and the decider (`CouchHomeSupport.pickEntries(for:)`).
    private func currentCouchPickIDs() -> Set<String>? {
        guard let couch = provider.picksCouch else { return nil }

        let entries = CouchHomeSupport.pickEntries(for: couch)
        return Set(entries.map(\.id))
    }

    /// A background refresh re-runs every row, including rows that were empty and hidden, so "Picked for…"
    /// appears, updates or disappears without the full-screen spinner and without moving the tvOS focus.
    private func refreshIfCouchPicksChanged() {
        guard let refreshedCouchPickIDs,
              let pickIDs = currentCouchPickIDs(),
              pickIDs != refreshedCouchPickIDs
        else { return }

        // A running refresh compares again when it ends
        guard state == .content, !background.is(.refreshing) else { return }

        logger.info("Couch picks changed, refreshing the home")
        background.refresh()
    }
}

// MARK: - Just arrived

@MainActor
extension ContentGroupViewModel {

    /// Refreshes the "Just arrived" rows when the arrivals for this couch's members change, for example
    /// when a slow `ReadyAlertsService` refresh ends after the row stopped waiting for it.
    private func observeArrivals() {
        let service = Container.shared.readyAlertsService()

        // `$arrivals` emits before the value is set, the debounce also lets several changes settle
        Publishers.Merge(
            service.$arrivals.map { _ in () },
            couchPicksCheck
        )
        .debounce(for: 1, scheduler: RunLoop.main)
        .sink { [weak self] _ in
            self?.refreshIfArrivalsChanged()
        }
        .store(in: &cancellables)
    }

    private func currentArrivalIDs() -> Set<String>? {
        guard let couch = provider.picksCouch else { return nil }

        let arrivals = Container.shared.readyAlertsService().arrivals(forMembers: couch.memberIDs)
        return Set(arrivals.map(\.id))
    }

    /// Only the "Just arrived" rows depend on the arrivals, so only they are refreshed in the background,
    /// without the full-screen spinner and without moving the tvOS focus.
    private func refreshIfArrivalsChanged() {
        guard let refreshedArrivalIDs,
              let arrivalIDs = currentArrivalIDs(),
              arrivalIDs != refreshedArrivalIDs
        else { return }

        // A running refresh compares again when it ends
        guard state == .content, !background.is(.refreshing), arrivalsRefreshTask == nil else { return }

        // Read before the row fetches: arrivals that change while it fetches trigger one more refresh
        self.refreshedArrivalIDs = arrivalIDs

        let justArrivedGroups = candidateGroups.compactMap { $0 as? PosterGroup<JustArrivedLibrary> }

        guard justArrivedGroups.isNotEmpty else { return }

        logger.info("Arrivals changed, refreshing Just arrived")

        arrivalsRefreshTask = Task { [weak self] in
            for group in justArrivedGroups {
                await group.viewModel.background.refresh()
            }

            guard let self else { return }

            self.arrivalsRefreshTask = nil

            // A refresh that started meanwhile shows the groups itself
            if self.state == .content, !self.background.is(.refreshing) {
                self.resolveGroups()
            }

            self.couchPicksCheck.send()
        }
    }
}
