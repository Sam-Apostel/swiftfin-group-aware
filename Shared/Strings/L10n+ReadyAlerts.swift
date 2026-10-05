//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// English strings for "It's ready" alerts (#24, #29, #30).
/// Kept out of the generated `Strings.swift` to avoid merge conflicts.
extension L10n {

    enum ReadyAlerts {

        static let justArrived = "Just arrived"
        static let itsReady = "It's ready"

        /// "Toy Story is ready for Sam, Lisa & Tuur"
        static func readyFor(_ title: String, names: String) -> String {
            "\(title) is ready for \(names)"
        }

        /// "Toy Story is ready"
        static func ready(_ title: String) -> String {
            "\(title) is ready"
        }

        /// "Toy Story and 2 more are ready"
        static func andMoreReady(_ title: String, count: Int) -> String {
            "\(title) and \(count) more are ready"
        }

        // MARK: - Settings

        static let showJustArrivedOnHome = "Show \"Just arrived\" on Home"
        static let tellUsWhenWeSitDown = "Tell us when we sit down"
        static let itsReadyFooter = "When something you tagged with Who's it for? or requested in Seerr lands in the library."

        static let notifications = "Notifications"
        static let notifyThisIPhone = "Notify this iPhone"
        static let notifyAbout = "Notify about"
        static let notificationsOff = "Notifications are off for Couchfin"
        static let openSettings = "Open Settings"
        static let backgroundRefreshOff = "Background App Refresh is off, so alerts only arrive when you open Couchfin."
        static let noUsers = "No signed-in users on this server"
    }
}
