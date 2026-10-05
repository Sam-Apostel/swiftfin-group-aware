//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import SwiftUI

extension EnvironmentValues {

    /// The tab coordinator of `MainTabView`, so a couch change can close every sheet before it signs in.
    ///
    /// `nil` outside of `MainTabView`, and inside presentations that don't carry the environment.
    @Entry
    var couchTabCoordinator: TabCoordinator? = nil
}

extension TabCoordinator {

    /// Whether any tab presents a sheet or a full-screen route.
    var isPresentingRoute: Bool {
        tabs.contains { tab in
            tab.coordinator.presentedSheet != nil || tab.coordinator.presentedFullScreen != nil
        }
    }

    /// Closes the sheets and full-screen routes of every tab, e.g. Settings with the couch switcher on top.
    func closeAllPresentedRoutes() {
        for tab in tabs {
            tab.coordinator.presentedSheet = nil
            tab.coordinator.presentedFullScreen = nil
        }
    }
}

extension View {

    /// Asks "Still Sam, Lisa & Tuur?" when `UserSessionManager.shouldConfirmCouch` is set.
    ///
    /// Attach it once, to `MainTabView`, with its tab coordinator. It also puts that coordinator in the
    /// environment (`couchTabCoordinator`) for the couch switcher.
    func couchStillHerePrompt(tabCoordinator: TabCoordinator) -> some View {
        modifier(CouchStillHereModifier(tabCoordinator: tabCoordinator))
    }
}

/// "Still Sam, Lisa & Tuur?" after a cold launch or a long break, so yesterday's couch doesn't
/// silently keep browsing (and echoing progress) for everyone.
///
/// - "Yes" comes first (default focus on tvOS) and keeps the couch.
/// - "Change…" opens the couch switcher, which runs the same PIN and grown-up checks as always.
/// - A solo couch never asks. It never shows during playback, and waits until no sheet is presented.
struct CouchStillHereModifier: ViewModifier {

    /// How often the prompt checks whether it can be shown.
    private static let pollInterval: Duration = .milliseconds(800)

    @InjectedObject(\.userSessionManager)
    private var userSessionManager: UserSessionManager

    let tabCoordinator: TabCoordinator

    @State
    private var isPresented = false
    /// The names in the title, in pick order.
    @State
    private var names: [String] = []

    func body(content: Content) -> some View {
        content
            .environment(\.couchTabCoordinator, tabCoordinator)
            .task(id: userSessionManager.shouldConfirmCouch) {
                await presentWhenReady()
            }
            .alert(
                L10n.CouchSwitcher.stillHereTitle(names),
                isPresented: $isPresented
            ) {
                Button(L10n.yes) {
                    keepCouch()
                }

                Button(L10n.CouchSwitcher.change) {
                    changeCouch()
                }
            } message: {
                Text(L10n.CouchSwitcher.stillHereMessage)
            }
            .onChange(of: isPresented) {
                // Dismissed without a button (e.g. Menu on the Siri Remote): keep the couch,
                // so the question isn't asked again right away
                guard !isPresented, userSessionManager.shouldConfirmCouch else { return }

                userSessionManager.confirmCouch()
            }
    }

    /// Waits until nothing is presented or playing, then asks.
    @MainActor
    private func presentWhenReady() async {
        guard userSessionManager.shouldConfirmCouch, !isPresented else { return }

        while !Task.isCancelled {
            // Also lets the home settle after a launch
            try? await Task.sleep(for: Self.pollInterval)

            guard !Task.isCancelled, userSessionManager.shouldConfirmCouch, !isPresented else { return }
            guard let couch = userSessionManager.currentSession?.couch, couch.isGroup else {
                // A solo couch never asks
                userSessionManager.confirmCouch()
                return
            }
            guard !userSessionManager.hasActivePlayback, !tabCoordinator.isPresentingRoute else { continue }

            names = userSessionManager
                .pickOrderedMemberIDs(of: couch)
                .compactMap { id in
                    couch.members.first { $0.id == id }?.username
                }
            isPresented = true
            return
        }
    }

    @MainActor
    private func keepCouch() {
        userSessionManager.confirmCouch()
    }

    @MainActor
    private func changeCouch() {
        userSessionManager.confirmCouch()

        let tabCoordinator = tabCoordinator

        Task { @MainActor in
            // A route that starts while the alert is still animating out can be dropped
            try? await Task.sleep(for: .milliseconds(400))

            await tabCoordinator.route(to: .couchSwitcher)
        }
    }
}
