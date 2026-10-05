//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Foundation

// `AppKey` is private to SwiftfinDefaults.swift, so these spell out the app suite.
extension Defaults.Keys {

    enum ReadyAlerts {

        /// Show the "Just arrived" row on Home.
        static let showJustArrivedRow = Defaults.Key<Bool>("readyAlertsShowJustArrivedRow", default: true, suite: .appSuite)

        /// Show the "It's ready" banner on launch and when a couch starts.
        static let showBanner = Defaults.Key<Bool>("readyAlertsShowBanner", default: true, suite: .appSuite)

        /// Send local notifications from this device (iOS).
        static let notificationsEnabled = Defaults.Key<Bool>("readyAlertsNotificationsEnabled", default: false, suite: .appSuite)

        /// The Jellyfin user ids this device sends notifications about (iOS).
        static let notifyUserIDs = Defaults.Key<[String]>("readyAlertsNotifyUserIDs", default: [], suite: .appSuite)
    }
}
