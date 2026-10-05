//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import FactoryKit
import SwiftUI

#if os(iOS)
import UserNotifications
#endif

/// The "It's ready" sections of Couch settings. Place it inside a `Form`.
///
/// - iOS and tvOS: the "Just arrived" row and the "It's ready" banner.
/// - iOS only: local notifications and whom this iPhone or iPad notifies about.
struct ReadyAlertsSettingsSection: View {

    @Default(.ReadyAlerts.showJustArrivedRow)
    private var showJustArrivedRow
    @Default(.ReadyAlerts.showBanner)
    private var showBanner

    #if os(iOS)
    @Default(.ReadyAlerts.notificationsEnabled)
    private var notificationsEnabled
    @Default(.ReadyAlerts.notifyUserIDs)
    private var notifyUserIDs

    @InjectedObject(\.userSessionManager)
    private var userSessionManager: UserSessionManager

    /// Stored users on the current server, sorted by name.
    @State
    private var users: [UserState] = []
    @State
    private var isPermissionDenied = false
    @State
    private var isBackgroundRefreshAvailable = true
    #endif

    init() {}

    var body: some View {
        alertsSection

        #if os(iOS)
        notificationsSection

        if notificationsEnabled {
            notifyAboutSection
        }
        #endif
    }

    // MARK: - It's ready

    @ViewBuilder
    private var alertsSection: some View {
        Section {
            Toggle(L10n.ReadyAlerts.showJustArrivedOnHome, isOn: $showJustArrivedRow)

            Toggle(L10n.ReadyAlerts.tellUsWhenWeSitDown, isOn: $showBanner)
        } header: {
            Text(L10n.ReadyAlerts.itsReady)
        } footer: {
            Text(L10n.ReadyAlerts.itsReadyFooter)
        }
    }

    #if os(iOS)

    // MARK: - Notifications

    @ViewBuilder
    private var notificationsSection: some View {
        Section {
            Toggle(
                UIDevice.isPad ? L10n.ReadyAlerts.notifyThisIPad : L10n.ReadyAlerts.notifyThisIPhone,
                isOn: notificationsBinding
            )
        } header: {
            Text(L10n.ReadyAlerts.notifications)
        } footer: {
            notificationsFooter
        }
        .onAppear {
            loadUsers()
            updateBackgroundRefreshStatus()
        }
        .task {
            await updateAuthorizationStatus()
        }
        .onNotification(.applicationWillEnterForeground) {
            // Back from the Settings app
            updateBackgroundRefreshStatus()

            Task {
                await updateAuthorizationStatus()
            }
        }
    }

    @ViewBuilder
    private var notificationsFooter: some View {
        if isPermissionDenied {
            VStack(alignment: .leading, spacing: 8) {
                Label(L10n.ReadyAlerts.notificationsOff, systemImage: "exclamationmark.circle.fill")
                    .labelStyle(.sectionFooterWithImage(imageStyle: .orange))

                Button(L10n.ReadyAlerts.openSettings) {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }

                    UIApplication.shared.open(url)
                }
                .foregroundStyle(Color.accentColor)
                .buttonStyle(.plain)
            }
        } else if notificationsEnabled, isBackgroundRefreshAvailable == false {
            Text(L10n.ReadyAlerts.backgroundRefreshOff)
        }
    }

    // MARK: - Notify about

    @ViewBuilder
    private var notifyAboutSection: some View {
        Section {
            if users.isEmpty {
                Text(L10n.ReadyAlerts.noUsers)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(users, id: \.id) { user in
                    Toggle(isOn: notifyBinding(for: user)) {
                        userRowLabel(user: user)
                    }
                }
            }
        } header: {
            Text(L10n.ReadyAlerts.notifyAbout)
        }
    }

    @ViewBuilder
    private func userRowLabel(user: UserState) -> some View {
        HStack(spacing: 12) {
            if let server = userSessionManager.currentSession?.server {
                UserProfileImage(
                    userID: user.id,
                    source: user.profileImageSource(
                        client: server.client
                    ),
                    pipeline: .Swiftfin.local
                )
                .frame(width: 36, height: 36)
            }

            Text(user.username)
                .lineLimit(1)
        }
    }

    // MARK: - Bindings

    private var notificationsBinding: Binding<Bool> {
        Binding(
            get: {
                notificationsEnabled
            },
            set: { isOn in
                if isOn {
                    enableNotifications()
                } else {
                    notificationsEnabled = false
                }
            }
        )
    }

    private func notifyBinding(for user: UserState) -> Binding<Bool> {
        Binding(
            get: {
                notifyUserIDs.contains(user.id)
            },
            set: { isOn in
                if isOn {
                    if notifyUserIDs.contains(user.id) == false {
                        notifyUserIDs.append(user.id)
                    }
                } else {
                    notifyUserIDs.removeAll { $0 == user.id }
                }
            }
        )
    }

    // MARK: - Helpers

    /// Turns notifications on, then asks for permission. Switches back off when it's denied.
    private func enableNotifications() {
        notificationsEnabled = true

        Task { @MainActor in
            let isGranted: Bool

            do {
                isGranted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                isGranted = false
            }

            guard isGranted else {
                notificationsEnabled = false
                isPermissionDenied = true
                return
            }

            isPermissionDenied = false

            if notifyUserIDs.isEmpty {
                notifyUserIDs = defaultNotifyUserIDs()
            }
        }
    }

    /// Whom to notify about when notifications are first turned on: the grown-ups on the couch,
    /// never a child (the primary may be the kid when kid-safe browsing is on).
    ///
    /// Falls back to the current user only when they are not a child (`isChildAudience`).
    private func defaultNotifyUserIDs() -> [String] {
        guard let currentSession = userSessionManager.currentSession else { return [] }

        let grownUpIDs = currentSession.couch.grownUps.map(\.id)

        if grownUpIDs.isNotEmpty {
            return grownUpIDs
        }

        if currentSession.user.isChildAudience {
            return []
        }

        return [currentSession.user.id]
    }

    @MainActor
    private func updateAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let isDenied = settings.authorizationStatus == .denied

        isPermissionDenied = isDenied

        if isDenied, notificationsEnabled {
            notificationsEnabled = false
        }
    }

    private func updateBackgroundRefreshStatus() {
        isBackgroundRefreshAvailable = UIApplication.shared.backgroundRefreshStatus == .available
    }

    private func loadUsers() {
        guard let serverID = userSessionManager.currentSession?.server.id else {
            users = []
            return
        }

        users = StoredValues[.User.users]
            .filter { $0.serverID == serverID }
            .sorted { $0.username.localizedStandardCompare($1.username) == .orderedAscending }
    }
    #endif
}
