//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// The people watching together on this device ("on the couch").
///
/// A couch always has at least one member: the `primary` user, which is the
/// account the app browses and plays as (`UserSession.user`). All members
/// belong to the same server as the primary user.
struct CouchGroup: Hashable, Identifiable {

    /// The account the app browses and plays as.
    let primary: UserState

    /// Everyone on the couch, with the primary user first.
    let members: [UserState]

    /// Creates a couch where `primary` is always the first member.
    ///
    /// Duplicate members, and members on a different server than
    /// the primary user, are dropped.
    init(primary: UserState, members: [UserState]) {
        self.primary = primary

        var seenIDs: Set<String> = [primary.id]
        var orderedMembers: [UserState] = [primary]

        for member in members where member.serverID == primary.serverID {
            guard seenIDs.insert(member.id).inserted else { continue }

            orderedMembers.append(member)
        }

        self.members = orderedMembers
    }

    /// A stable identifier for this set of members, independent of the pick order.
    var id: String {
        "couch-" + members.map(\.id).sorted().joined(separator: "_")
    }

    var memberIDs: Set<String> {
        Set(members.map(\.id))
    }

    /// Every member except the primary user.
    var otherMembers: [UserState] {
        members.filter { $0.id != primary.id }
    }

    /// Whether more than one person is on the couch.
    var isGroup: Bool {
        members.count > 1
    }

    /// Whether a child is on the couch (`UserState.isChildAudience`:
    /// marked as a kid, or a server age limit below 12).
    var hasChild: Bool {
        members.contains(where: \.isChildAudience)
    }

    /// Whether everyone on the couch is a child (`UserState.isChildAudience`).
    var isChildrenOnly: Bool {
        members.allSatisfy(\.isChildAudience)
    }

    /// Whether anyone on the couch is restricted (a kid, or any server age limit).
    var hasRestrictedMember: Bool {
        members.contains(where: \.isRestricted)
    }

    /// The members that are not restricted, in couch order (primary first).
    var grownUps: [UserState] {
        members.filter { !$0.isRestricted }
    }

    /// A localized list of the member names, e.g. "Sam, Lisa and Tuur".
    var displayNames: String {
        let names = members.map(\.username)
        return ListFormatter.localizedString(byJoining: names)
    }

    /// A couch with only the given user.
    static func solo(_ user: UserState) -> CouchGroup {
        CouchGroup(primary: user, members: [user])
    }
}
