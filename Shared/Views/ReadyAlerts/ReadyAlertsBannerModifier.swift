//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import FactoryKit
import JellyfinAPI
import SwiftUI
import UIKit

extension View {

    /// Tells the people on the couch what they were waiting for: "Toy Story is ready for Lisa & Sam".
    ///
    /// Attach it once, to the tab root (`MainTabView`). That view is rebuilt on every sign-in and couch change,
    /// so the check runs on launch and on every couch start, and again when the app comes to the foreground.
    /// iOS shows a top banner card, tvOS the native alert.
    func readyAlertsBanner() -> some View {
        modifier(ReadyAlertsBannerModifier())
    }
}

struct ReadyAlertsBannerModifier: ViewModifier {

    /// What one check found to announce.
    struct Announcement: Identifiable {

        let id = UUID()

        /// "Toy Story is ready for Lisa & Sam", or "Toy Story and 2 more are ready".
        let message: String

        /// The library item of the first arrival, opened by "Watch now" or a tap on the banner.
        let item: BaseItemDto?
    }

    /// Lets the home and its focus settle before announcing.
    private static let settleDelay: Duration = .seconds(2)

    /// How often a found arrival checks whether "Still Sam, Lisa & Tuur?" was answered.
    private static let couchConfirmationPollInterval: Duration = .milliseconds(500)

    #if os(iOS)
    /// How long the banner stays on screen.
    private static let autoDismissDelay: Duration = .seconds(8)
    #endif

    @State
    private var announcement: Announcement?
    @State
    private var isChecking = false

    #if os(iOS)
    @Environment(\.accessibilityVoiceOverEnabled)
    private var isVoiceOverEnabled
    #endif

    /// Set by `couchStillHerePrompt(tabCoordinator:)`, which wraps this modifier in `MainTabView`.
    @Environment(\.couchTabCoordinator)
    private var couchTabCoordinator

    func body(content: Content) -> some View {
        content
            .task {
                await announceIfNeeded()
            }
            .onSceneWillEnterForeground {
                Task {
                    await announceIfNeeded()
                }
            }
            #if os(iOS)
            .overlay(alignment: .top) {
                ZStack(alignment: .top) {
                    bannerOverlay
                }
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: announcement?.id)
            }
            .task(id: announcement?.id) {
                await autoDismiss()
            }
            #else
            .alert(
                L10n.ReadyAlerts.itsReady,
                isPresented: isAlertPresented,
                presenting: announcement
            ) { announcement in
                if let item = announcement.item {
                    Button(L10n.ReadyAlertsBanner.watchNow) {
                        open(item)
                    }
                }

                Button(L10n.ReadyAlertsBanner.later, role: .cancel) {}
            } message: { announcement in
                Text(announcement.message)
            }
            #endif
    }

    // MARK: - iOS banner

    #if os(iOS)
    @ViewBuilder
    private var bannerOverlay: some View {
        if let announcement {
            ReadyAlertsBannerCard(
                message: announcement.message,
                item: announcement.item
            ) {
                if let item = announcement.item {
                    open(item)
                }
                dismiss()
            } onDismiss: {
                dismiss()
            }
            .id(announcement.id)
            .frame(maxWidth: 500)
            .padding(.horizontal, EdgeInsets.edgePadding)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
            .onAppear {
                UIDevice.feedback(.success)
                UIAccessibility.post(notification: .announcement, argument: announcement.message)
            }
        }
    }

    @MainActor
    private func autoDismiss() async {
        guard announcement != nil else { return }

        // VoiceOver users need longer than a few seconds to reach the banner.
        guard !isVoiceOverEnabled else { return }

        try? await Task.sleep(for: Self.autoDismissDelay)

        guard !Task.isCancelled else { return }

        dismiss()
    }
    #endif

    // MARK: - tvOS alert

    #if os(tvOS)
    private var isAlertPresented: Binding<Bool> {
        Binding(
            get: { announcement != nil },
            set: { isPresented in
                if !isPresented {
                    announcement = nil
                }
            }
        )
    }
    #endif

    // MARK: - Actions

    @MainActor
    private func dismiss() {
        announcement = nil
    }

    @MainActor
    private func open(_ item: BaseItemDto) {
        let userSessionManager = Container.shared.userSessionManager()

        Task { @MainActor in
            #if os(tvOS)
            // A push that starts while the alert is still animating out can be dropped.
            try? await Task.sleep(for: .milliseconds(400))
            #endif

            userSessionManager.routePublisher.send(.item(item: item))
        }
    }

    /// Waits while "Still Sam, Lisa & Tuur?" is unanswered, then until its alert and any sheet it opened
    /// ("Change…" opens the couch switcher) are gone. Only one alert can show at a time, and arrivals
    /// are recorded as announced before they are presented, so a collision would lose them.
    ///
    /// - Returns: `false` when cancelled.
    @MainActor
    private func waitForCouchConfirmation(userSessionManager: UserSessionManager) async -> Bool {
        guard userSessionManager.shouldConfirmCouch else { return true }

        var clearChecks = 0

        // Three clear checks in a row: the alert finished animating out, and a route started by
        // "Change…" (after a short delay) is seen
        while clearChecks < 3 {
            if userSessionManager.shouldConfirmCouch || couchTabCoordinator?.isPresentingRoute == true {
                clearChecks = 0
            } else {
                clearChecks += 1
            }

            try? await Task.sleep(for: Self.couchConfirmationPollInterval)

            guard !Task.isCancelled else { return false }
        }

        return true
    }

    /// Refreshes the arrivals and presents the ones nobody on the couch was told about on this device.
    ///
    /// The arrivals are recorded as announced **before** they are presented,
    /// so a kill or a crash never repeats an announcement.
    @MainActor
    private func announceIfNeeded() async {
        guard !isChecking, announcement == nil else { return }

        isChecking = true
        defer { isChecking = false }

        try? await Task.sleep(for: Self.settleDelay)

        guard !Task.isCancelled, Defaults[.ReadyAlerts.showBanner] else { return }

        let userSessionManager = Container.shared.userSessionManager()

        guard !userSessionManager.hasActivePlayback,
              let session = userSessionManager.currentSession
        else { return }

        let service = Container.shared.readyAlertsService()

        await service.refresh(session: session)

        guard await waitForCouchConfirmation(userSessionManager: userSessionManager) else { return }

        // Playback may have started, or the couch changed, while refreshing.
        guard !Task.isCancelled,
              announcement == nil,
              !userSessionManager.hasActivePlayback,
              userSessionManager.currentSession === session
        else { return }

        let memberIDs = session.couch.memberIDs
        let pending = service.unannouncedArrivals(forMembers: memberIDs)

        guard let first = pending.first else { return }

        service.markAnnounced(pending, to: memberIDs)

        let message = pending.count == 1
            ? service.message(for: first)
            : service.summaryMessage(for: pending)

        announcement = Announcement(
            message: message,
            item: service.item(for: first)
        )
    }
}
