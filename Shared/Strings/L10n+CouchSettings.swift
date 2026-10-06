//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

// MARK: - Home title

extension L10n.Couch {

    /// The home navigation title for a couch. Never "Together": everyone sees who it is for.
    ///
    /// - One member: their name, e.g. "Sam".
    /// - Two members: both names, e.g. "Sam & Lisa".
    /// - Three members: every name, e.g. "Sam, Lisa & Tuur".
    /// - Four or more: the first name and how many others, e.g. "Sam & 3 others".
    ///
    /// Grown-ups come first, in pick order, so a kid-safe couch that browses as Tuur still reads
    /// "Sam, Lisa & Tuur" (`CouchGroup.members` puts the primary user first).
    static func homeTitle(couch: CouchGroup) -> String {
        let names = (couch.grownUps + couch.members.filter(\.isRestricted)).map(\.username)

        switch names.count {
        case 0:
            return L10n.home
        case 1:
            return names[0]
        case 2:
            return "\(names[0]) & \(names[1])"
        case 3:
            return "\(names[0]), \(names[1]) & \(names[2])"
        default:
            return "\(names[0]) & \(names.count - 1) others"
        }
    }
}

// MARK: - Couch settings

extension L10n {

    enum CouchSettings {

        static let couchSettings = "Couch settings"
        static let changeWhosWatching = "Change who's watching"
        static let together = "Together"

        static let kidSafeBrowsingFooter =
            "With a kid on the couch, Couchfin browses as the most restricted person, so their Jellyfin parental controls apply. Turning this off asks a grown-up."

        static let hideWatchedByAnyMember = "Hide what anyone already watched"
        static let hideWatchedByAnyMemberFooter =
            "Hides titles anyone on the couch has watched from New for All of You and What should we watch?"

        static let kids = "Kids"
        static let kidsFooter =
            "Kids get kid-friendly rows, suggestions and Seerr. Applies on every device in the household."
        static let noUsers = "No users on this server yet"

        static let kid = "Kid"

        /// - Parameter names: A localized list of names, e.g. `CouchGroup.displayNames`.
        static func onTheCouch(_ names: String) -> String {
            "On the couch: \(names)"
        }

        /// - Parameter name: The name of the account the app browses as.
        static func browsingAsKidSafe(_ name: String) -> String {
            "Browsing as \(name) (kid-safe)"
        }

        // MARK: No age limit

        /// Under a kid without a maximum parental rating on their Jellyfin account.
        static func noAgeLimit(_ name: String) -> String {
            "No age limit on \(name)'s Jellyfin account — grown-up titles can still show."
        }

        static let setAgeLimit = "Set age limit…"
        static let setAgeLimitInDashboard = "Set it in the Jellyfin dashboard (needs an admin account)."
        static let setAgeLimitElsewhere = "Set it on your iPhone or in the Jellyfin dashboard."

        // MARK: Grown-up lock

        static let grownUpLock = "Grown-up lock"

        /// "Tuur can start this Apple TV as Sam — Sam has no PIN here."
        ///
        /// - Parameters:
        ///   - kids: A localized list of the children's names.
        ///   - device: "iPhone", "iPad" or "Apple TV".
        ///   - grownUps: The names of the grown-ups without a PIN on this device.
        static func grownUpLockWarning(kids: String, device: String, grownUps: [String]) -> String {
            let names = ListFormatter.localizedString(byJoining: grownUps)

            if grownUps.count == 1 {
                return "\(kids) can start this \(device) as \(names) — \(names) has no PIN here."
            }

            return "\(kids) can start this \(device) as \(names) — they have no PIN here."
        }

        static func setPinFor(_ name: String) -> String {
            "Set a PIN for \(name)…"
        }

        static func grownUpLockFooter(device: String) -> String {
            "A PIN stops anyone from starting this \(device) as a grown-up, and lets a grown-up approve turning kid protection off. PINs are kept on this \(device) only."
        }

        // MARK: Grown-up check

        /// Added to the "no PIN" confirmation when the Grown-up lock section is shown.
        static let setPinUnderGrownUpLock = "Set a PIN under Grown-up lock."

        // MARK: Apply

        /// - Parameter name: The member the couch would browse as.
        static func applyNow(_ name: String) -> String {
            "Apply now — browse as \(name)"
        }

        static let stopPlaybackToApply = "Stop playback to apply."
        static let takesEffectNextCouch = "Takes effect the next time you start a couch."
    }
}
