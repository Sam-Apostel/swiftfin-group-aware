//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import Foundation
import Logging
import UIKit
import UserNotifications

/// The app's `UNUserNotificationCenter` delegate, set by `ReadyAlertsBackgroundRefresh.register()`.
///
/// - In the foreground, "It's ready" notifications only go to Notification Center: the in-app banner is the foreground surface.
/// - A tap opens the item through the existing deep-link flow (`UserSessionManager.handleOpenURL`),
///   which handles local authentication, switching users and routing.
final class ReadyAlertsNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {

    static let shared = ReadyAlertsNotificationDelegate()

    /// The thread all "It's ready" notifications are grouped in.
    static let threadIdentifier = "ready-alerts"
    /// The request identifier of the summary notification (more than 3 arrivals in one run).
    static let summaryIdentifier = "ready-alerts-summary"
    /// `userInfo` key of the `swiftfin://<serverID>/<userID>/item/<itemID>` link.
    static let deepLinkKey = "deepLink"

    /// How long a tap waits for the stored session to be restored on a cold launch.
    private static let sessionRestoreTimeout: TimeInterval = 5

    private static let logger = Logger.swiftfin()

    override private init() {
        super.init()
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if notification.request.content.threadIdentifier == Self.threadIdentifier {
            completionHandler([.list])
        } else {
            completionHandler([.banner, .list, .sound])
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer {
            completionHandler()
        }

        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        guard let link = response.notification.request.content.userInfo[Self.deepLinkKey] as? String,
              let url = URL(string: link),
              let deepLink = DeepLink(url)
        else { return }

        Task { @MainActor in
            await Self.open(deepLink, url: url)
        }
    }

    // MARK: - Tap

    /// Routes straight to the item when the current session can show it, otherwise opens the link,
    /// which goes through `onOpenURL` → `UserSessionManager.handleOpenURL`.
    @MainActor
    private static func open(_ deepLink: DeepLink, url: URL) async {
        let userSessionManager = Container.shared.userSessionManager()

        // A tap that cold-launches the app arrives before the stored session is restored
        let deadline = Date.now.addingTimeInterval(sessionRestoreTimeout)

        while userSessionManager.state == .initial, Date.now < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }

        if userSessionManager.state == .signedIn,
           let currentSession = userSessionManager.currentSession,
           currentSession.server.id == deepLink.serverID,
           currentSession.couch.members.contains(where: { $0.id == deepLink.userID })
        {
            // Already that user (or they're on the couch): don't break up the couch.
            // Give `MainTabView` a moment to subscribe to the route publisher after a cold launch.
            try? await Task.sleep(for: .milliseconds(500))

            userSessionManager.routePublisher.send(deepLink.route())
            return
        }

        let didOpen = await UIApplication.shared.open(url, options: [:])

        if didOpen == false {
            logger.error("Ready alerts: opening the notification's item link failed")
        }
    }
}
