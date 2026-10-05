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

// `AppKey` is private to SwiftfinDefaults.swift, so these spell out the app suite.
// Every key is per Jellyfin server; Defaults key names can't contain dots.
extension Defaults.Keys {

    /// The zero-click Seerr setup on Apple TV (`SeerrTVSetupViewModel`).
    enum SeerrTVSetup {

        /// Someone explicitly signed out of Seerr, or disconnected it, in the tvOS Seerr settings.
        ///
        /// While set, the Discover tab never signs the couch in by itself. A manual sign-in clears it.
        static func signedOutExplicitly(serverID: String) -> Defaults.Key<Bool> {
            Defaults.Key<Bool>(
                "seerrTVSignedOutExplicitly_\(storageID(serverID))",
                default: false,
                suite: .appSuite
            )
        }

        /// Someone on this device had a Seerr session for this Jellyfin server at least once.
        static func hadSession(serverID: String) -> Defaults.Key<Bool> {
            Defaults.Key<Bool>(
                "seerrTVHadSession_\(storageID(serverID))",
                default: false,
                suite: .appSuite
            )
        }

        /// Whether this device's Seerr URL came from the household (read-only here).
        ///
        /// The same key as the private `SeerrService.householdAdoptedKey(serverID:)`
        /// (SeerrService+Household.swift): keep the name and suite in sync. Only `SeerrService` writes it.
        static func householdAdopted(serverID: String) -> Defaults.Key<Bool> {
            Defaults.Key<Bool>(
                "seerrHouseholdAdopted_\(storageID(serverID))",
                default: false,
                suite: .appSuite
            )
        }

        private static func storageID(_ serverID: String) -> String {
            serverID.replacing(".", with: "_")
        }
    }
}

/// Reads and writes the `Defaults.Keys.SeerrTVSetup` flags for the current Jellyfin server.
enum SeerrTVSetupFlags {

    private static var currentServerID: String? {
        Container.shared.currentUserSession()?.server.id
    }

    /// An explicit Sign out or Disconnect: the Discover tab stops signing in by itself.
    static func noteExplicitSignOut() {
        guard let serverID = currentServerID else { return }

        Defaults[Defaults.Keys.SeerrTVSetup.signedOutExplicitly(serverID: serverID)] = true
    }

    /// A manual sign-in: the Discover tab may sign in by itself again.
    static func clearExplicitSignOut() {
        guard let serverID = currentServerID else { return }

        Defaults[Defaults.Keys.SeerrTVSetup.signedOutExplicitly(serverID: serverID)] = false
    }

    static var isSignedOutExplicitly: Bool {
        guard let serverID = currentServerID else { return false }

        return Defaults[Defaults.Keys.SeerrTVSetup.signedOutExplicitly(serverID: serverID)]
    }

    /// Remembers that someone here had a Seerr session for the current server.
    static func noteSession() {
        guard let serverID = currentServerID else { return }

        let key = Defaults.Keys.SeerrTVSetup.hadSession(serverID: serverID)

        if !Defaults[key] {
            Defaults[key] = true
        }
    }

    static var hadSession: Bool {
        guard let serverID = currentServerID else { return false }

        return Defaults[Defaults.Keys.SeerrTVSetup.hadSession(serverID: serverID)]
    }

    static var isHouseholdAdopted: Bool {
        guard let serverID = currentServerID else { return false }

        return Defaults[Defaults.Keys.SeerrTVSetup.householdAdopted(serverID: serverID)]
    }
}
