//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import BackgroundTasks
import Defaults
import Foundation
import Logging
import UIKit
import UserNotifications

/// Background App Refresh for "It's ready" notifications.
///
/// `register()` is called once from `SwiftfinApp.init()`, before launch finishes, as `BGTaskScheduler` requires.
/// The identifier must be listed in the Info.plist's `BGTaskSchedulerPermittedIdentifiers`.
///
/// Uses `BGTaskScheduler` directly, never SwiftUI's `.backgroundTask(.appRefresh(…))` as well:
/// registering an identifier twice crashes.
enum ReadyAlertsBackgroundRefresh {

    /// `"<bundle id>.ready-alerts"`: `"land.sams.swiftfin.ready-alerts"`.
    static var taskIdentifier: String {
        (Bundle.main.bundleIdentifier ?? "land.sams.swiftfin") + ".ready-alerts"
    }

    /// The earliest a scheduled run may start. iOS picks the real time, typically a few times a day.
    static let earliestBeginInterval: TimeInterval = 60 * 60

    private static let logger = Logger.swiftfin()

    /// Main thread only: `register()` runs in `SwiftfinApp.init()`, `schedule()` on the main queue.
    private static var isRegistered = false
    private static var isTaskRegistered = false
    private static var didEnterBackgroundObserver: NSObjectProtocol?

    // MARK: - Register

    /// Registers the refresh handler and the notification delegate, and schedules a run whenever the app
    /// enters the background. Does nothing after the first call.
    static func register() {
        guard isRegistered == false else { return }

        isRegistered = true

        // Early enough to receive a tap that cold-launches the app
        UNUserNotificationCenter.current().delegate = ReadyAlertsNotificationDelegate.shared

        didEnterBackgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            schedule()
        }

        // Registering an identifier that isn't in the Info.plist is an assertion crash at launch
        let permittedIdentifiers = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String] ?? []

        guard permittedIdentifiers.contains(taskIdentifier) else {
            logger.error("Ready alerts: \(taskIdentifier) is not in BGTaskSchedulerPermittedIdentifiers, background refresh is off")
            return
        }

        isTaskRegistered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: .main
        ) { task in
            handle(task)
        }

        if isTaskRegistered == false {
            logger.error("Ready alerts: registering the background refresh task failed")
        }
    }

    // MARK: - Schedule

    /// Asks iOS for a refresh in an hour or later, while notifications are on and someone is notified about.
    /// Otherwise cancels the pending request.
    static func schedule() {
        guard isTaskRegistered else { return }
        guard Defaults[.ReadyAlerts.notificationsEnabled],
              Defaults[.ReadyAlerts.notifyUserIDs].isEmpty == false
        else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
            return
        }

        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: earliestBeginInterval)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Always on the Simulator (unavailable), and when Background App Refresh is off
            logger.warning("Ready alerts: scheduling the background refresh failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Run

    private static func handle(_ task: BGTask) {
        // Chain the next run first, so an expired run doesn't end the chain
        schedule()

        let completion = TaskCompletion(task: task)

        let work = Task { @MainActor in
            let posted = await ReadyAlertsNotifier.checkAndNotify()

            logger.info("Ready alerts: background refresh posted \(posted) notification(s)")

            completion.complete(success: Task.isCancelled == false)
        }

        task.expirationHandler = {
            work.cancel()
            completion.complete(success: false)
        }
    }
}

// MARK: - TaskCompletion

/// Calls `setTaskCompleted(success:)` exactly once, from the work or the expiration handler.
private final class TaskCompletion: @unchecked Sendable {

    private let task: BGTask
    private let lock = NSLock()
    private var isCompleted = false

    init(task: BGTask) {
        self.task = task
    }

    func complete(success: Bool) {
        lock.lock()
        let shouldComplete = isCompleted == false
        isCompleted = true
        lock.unlock()

        guard shouldComplete else { return }

        task.setTaskCompleted(success: success)
    }
}
