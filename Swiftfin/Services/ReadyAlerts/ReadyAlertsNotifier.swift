//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import FactoryKit
import Foundation
import Logging
import UIKit
import UserNotifications

/// Posts "It's ready" local notifications for the arrivals this iPhone wasn't told about yet.
///
/// Runs from Background App Refresh (`ReadyAlertsBackgroundRefresh`). Never throws: every reason not to post
/// (notifications off, no permission, phone locked, no token, Jellyfin unreachable) is logged and the run ends quietly.
@MainActor
enum ReadyAlertsNotifier {

    /// More new arrivals than this in one run are posted as one summary notification.
    static let summaryThreshold = 3

    private static let logger = Logger.swiftfin()

    // MARK: - Run

    /// Refreshes the arrivals and posts a notification for each one some notified user wasn't told about yet
    /// on this device, or one summary when there are more than `summaryThreshold`. Then records them as announced.
    ///
    /// - Returns: the number of notifications posted.
    @discardableResult
    static func checkAndNotify(now: Date = .now) async -> Int {
        guard Defaults[.ReadyAlerts.notificationsEnabled] else {
            logger.info("Ready alerts: notifications are off")
            return 0
        }

        let notifyUserIDs = Set(Defaults[.ReadyAlerts.notifyUserIDs])

        guard notifyUserIDs.isEmpty == false else {
            logger.info("Ready alerts: nobody to notify about")
            return 0
        }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            logger.info("Ready alerts: notifications aren't authorized")
            return 0
        }

        // Jellyfin tokens are in the keychain as "accessible when unlocked": a locked phone can't read them
        guard UIApplication.shared.isProtectedDataAvailable else {
            logger.info("Ready alerts: the phone is locked, skipping this run")
            return 0
        }
        guard let session = alertSession() else {
            logger.info("Ready alerts: no signed-in user with an access token to check for")
            return 0
        }

        let service = Container.shared.readyAlertsService()
        let refreshStart = Date.now

        await service.refresh(session: session, force: true)

        guard Task.isCancelled == false else {
            logger.info("Ready alerts: run cancelled")
            return 0
        }

        // A refresh that failed (Jellyfin unreachable) keeps the old arrivals and date: post nothing
        guard let lastRefreshDate = service.lastRefreshDate, lastRefreshDate >= refreshStart else {
            logger.warning("Ready alerts: refreshing the arrivals failed, nothing posted")
            return 0
        }

        let pending = service
            .unannouncedArrivals(notifying: notifyUserIDs)
            .filter { ReadyAlertRules.isRecent($0.arrivedAt, now: now) }

        guard pending.isEmpty == false else {
            logger.info("Ready alerts: nothing new")
            return 0
        }

        let posted: [ReadyArrival]
        let postedCount: Int

        if pending.count > summaryThreshold {
            let summary = summaryRequest(for: pending, service: service)

            if await add(summary, center: center) {
                posted = pending
                postedCount = 1
            } else {
                posted = []
                postedCount = 0
            }
        } else {
            var postedArrivals: [ReadyArrival] = []

            for arrival in pending {
                let notification = arrivalRequest(
                    for: arrival,
                    service: service,
                    serverID: session.server.id,
                    notifyUserIDs: notifyUserIDs
                )

                if await add(notification, center: center) {
                    postedArrivals.append(arrival)
                }
            }

            posted = postedArrivals
            postedCount = postedArrivals.count
        }

        service.markAnnounced(posted, to: notifyUserIDs)

        return postedCount
    }

    // MARK: - Session

    /// The session to check arrivals with.
    ///
    /// - The current session, when it's on a notified user's server (the app was only suspended, so Seerr works too).
    /// - Otherwise an inert session for the first notified user with a stored token, preferring the last signed-in user.
    ///   It's never started (no sockets) and works after "sign out on background", which only clears `lastSignedInUserID`.
    static func alertSession() -> UserSession? {
        let notifyUserIDs = Defaults[.ReadyAlerts.notifyUserIDs]

        guard notifyUserIDs.isEmpty == false else { return nil }

        let storedUsers = StoredValues[.User.users]
        var notifyUsers = notifyUserIDs.compactMap { id in
            storedUsers.first { $0.id == id }
        }

        if let currentSession = Container.shared.currentUserSession(),
           notifyUsers.contains(where: { $0.serverID == currentSession.server.id }),
           currentSession.user.storedAccessToken != nil
        {
            return currentSession
        }

        if case let .signedIn(lastUserID) = Defaults[.lastSignedInUserID],
           let index = notifyUsers.firstIndex(where: { $0.id == lastUserID })
        {
            let lastUser = notifyUsers.remove(at: index)
            notifyUsers.insert(lastUser, at: 0)
        }

        let servers = StoredValues[.Server.servers]

        for user in notifyUsers where user.storedAccessToken != nil {
            guard let server = servers.first(where: { $0.id == user.serverID }) else { continue }

            return UserSession(
                server: server,
                user: user,
                couch: nil,
                isCouchMember: true
            )
        }

        return nil
    }

    // MARK: - Requests

    /// One arrival: replaces an earlier notification of the same arrival instead of duplicating it.
    private static func arrivalRequest(
        for arrival: ReadyArrival,
        service: ReadyAlertsService,
        serverID: String,
        notifyUserIDs: Set<String>
    ) -> UNNotificationRequest {
        let content = baseContent()
        content.body = service.message(for: arrival)

        if let url = deepLinkURL(for: arrival, serverID: serverID, notifyUserIDs: notifyUserIDs) {
            content.userInfo = [ReadyAlertsNotificationDelegate.deepLinkKey: url.absoluteString]
        }

        return UNNotificationRequest(
            identifier: arrival.id,
            content: content,
            trigger: nil
        )
    }

    /// "Toy Story and 4 more are ready". A tap opens the app.
    private static func summaryRequest(
        for arrivals: [ReadyArrival],
        service: ReadyAlertsService
    ) -> UNNotificationRequest {
        let content = baseContent()
        content.body = service.summaryMessage(for: arrivals)

        return UNNotificationRequest(
            identifier: ReadyAlertsNotificationDelegate.summaryIdentifier,
            content: content,
            trigger: nil
        )
    }

    private static func baseContent() -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = L10n.ReadyAlerts.itsReady
        content.sound = .default
        content.threadIdentifier = ReadyAlertsNotificationDelegate.threadIdentifier
        return content
    }

    /// `swiftfin://<serverID>/<userID>/item/<itemID>`, opened as a notified audience member
    /// (the last signed-in user when they're one of them), so the existing deep-link flow
    /// handles local authentication, switching users and routing.
    private static func deepLinkURL(
        for arrival: ReadyArrival,
        serverID: String,
        notifyUserIDs: Set<String>
    ) -> URL? {
        let usersOnServer = Set(
            StoredValues[.User.users]
                .filter { $0.serverID == serverID }
                .map(\.id)
        )
        let candidates = arrival.audience
            .intersection(notifyUserIDs)
            .intersection(usersOnServer)

        let userID: String? = if case let .signedIn(lastUserID) = Defaults[.lastSignedInUserID], candidates.contains(lastUserID) {
            lastUserID
        } else {
            Defaults[.ReadyAlerts.notifyUserIDs].first { candidates.contains($0) } ?? candidates.min()
        }

        guard let userID else { return nil }

        return URL(string: "swiftfin://\(serverID)/\(userID)/item/\(arrival.jellyfinItemID)")
    }

    /// Posts a request. Never throws.
    private static func add(_ request: UNNotificationRequest, center: UNUserNotificationCenter) async -> Bool {
        do {
            try await center.add(request)
            return true
        } catch {
            logger.error("Ready alerts: posting a notification failed: \(error.localizedDescription)")
            return false
        }
    }
}
