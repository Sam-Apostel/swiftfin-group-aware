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

    /// The ids of the watchlist picks for exactly the couch (`provider.picksCouch`)
    /// when the groups were last refreshed. `nil` until the first refresh, or when the provider has no couch.
    private var refreshedCouchPickIDs: Set<String>?
    /// Asks for one more picks comparison, e.g. after a refresh ended.
    private let couchPicksCheck = PassthroughSubject<Void, Never>()

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
        // Read before the rows fetch: picks that change while they fetch trigger one more refresh
        refreshedCouchPickIDs = currentCouchPickIDs()

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

        try await refreshViewModels(
            for: newGroups,
            inBackground: false
        )

        candidateGroups = newGroups
        resolveGroups()
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

    private func currentCouchPickIDs() -> Set<String>? {
        guard let couch = provider.picksCouch else { return nil }

        let entries = Container.shared.audienceWatchlistStore().entries(forExactAudience: couch.memberIDs)
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
