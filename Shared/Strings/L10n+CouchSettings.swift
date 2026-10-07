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

    /// The home navigation title for a couch.
    ///
    /// - One member: their name, e.g. "Sam".
    /// - Two members: both names, e.g. "Sam & Lisa".
    /// - Three or more: "Together".
    static func homeTitle(couch: CouchGroup) -> String {
        let names = couch.members.map(\.username)

        switch names.count {
        case 0:
            return L10n.CouchSettings.together
        case 1:
            return names[0]
        case 2:
            return "\(names[0]) & \(names[1])"
        default:
            return L10n.CouchSettings.together
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
            "When a kid or someone with parental controls is on the couch, Couchfin browses as the most restricted person, so their Jellyfin parental controls apply. Takes effect the next time you start a couch."

        static let hideWatchedByAnyMember = "Hide what anyone already watched"
        static let hideWatchedByAnyMemberFooter =
            "Couch rows on Home skip anything that someone on the couch has already watched."

        static let kids = "Kids"
        static let kidsFooter =
            "Kids get kid-safe browsing and their own picks. Tip: also set a parental rating on their Jellyfin account."
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
    }
}
