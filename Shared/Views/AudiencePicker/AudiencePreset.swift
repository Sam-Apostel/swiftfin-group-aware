//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Foundation

extension Defaults.Keys {

    /// The most recently saved audiences, newest first.
    /// Each element is a comma-joined, sorted list of Jellyfin user ids.
    static let audienceRecentSets = Key<[String]>("audienceRecentSets", default: [], suite: .appSuite)
}

/// A quick-pick chip in the audience picker ("Just me", "The couch", ...).
struct AudiencePreset: Hashable, Identifiable {

    enum Kind: Hashable {
        case quick
        case recent
    }

    let id: String
    let title: String
    let systemImage: String
    let memberIDs: Set<String>
    let kind: Kind
}

extension AudiencePreset {

    private static let maximumRecents = 3
    private static let storedRecents = 12

    /// Builds the quick chips (Just me, The couch, Everyone, one per kid) followed by
    /// up to 3 recently used audiences. Presets with the same members are only shown once.
    static func presets(
        users: [UserState],
        primaryID: String?,
        couchIDs: Set<String>,
        kidIDs: Set<String>,
        recents: [Set<String>]
    ) -> [AudiencePreset] {
        let userIDs = Set(users.map(\.id))
        var candidates: [AudiencePreset] = []

        if let primaryID, userIDs.contains(primaryID) {
            candidates.append(
                AudiencePreset(
                    id: "just-me",
                    title: L10n.Audience.justMe,
                    systemImage: "person.fill",
                    memberIDs: [primaryID],
                    kind: .quick
                )
            )
        }

        let couch = couchIDs.intersection(userIDs)
        if couch.count > 1 {
            candidates.append(
                AudiencePreset(
                    id: "couch",
                    title: L10n.Audience.theCouch,
                    systemImage: "sofa.fill",
                    memberIDs: couch,
                    kind: .quick
                )
            )
        }

        if userIDs.count > 1 {
            candidates.append(
                AudiencePreset(
                    id: "everyone",
                    title: L10n.Audience.everyone,
                    systemImage: "person.3.fill",
                    memberIDs: userIDs,
                    kind: .quick
                )
            )
        }

        for user in users where kidIDs.contains(user.id) {
            candidates.append(
                AudiencePreset(
                    id: "kid-\(user.id)",
                    title: user.username,
                    systemImage: "figure.child",
                    memberIDs: [user.id],
                    kind: .quick
                )
            )
        }

        var seen: Set<Set<String>> = []
        var presets = candidates.filter { seen.insert($0.memberIDs).inserted }

        var recentCount = 0
        for recent in recents where recentCount < maximumRecents {
            // Only offer recents that can be fully shown with the people on this server
            guard recent.isNotEmpty, recent.isSubset(of: userIDs), seen.insert(recent).inserted else { continue }

            let names = users
                .filter { recent.contains($0.id) }
                .map(\.username)

            presets.append(
                AudiencePreset(
                    id: "recent-\(recent.sorted().joined(separator: "_"))",
                    title: L10n.Audience.joinedNames(names),
                    systemImage: "clock.arrow.circlepath",
                    memberIDs: recent,
                    kind: .recent
                )
            )
            recentCount += 1
        }

        return presets
    }

    // MARK: - Recents

    static var recentAudiences: [Set<String>] {
        Defaults[.audienceRecentSets].map { token in
            Set(token.split(separator: ",").map(String.init))
        }
    }

    static func recordRecent(_ audience: Set<String>) {
        guard audience.isNotEmpty else { return }

        let token = audience.sorted().joined(separator: ",")
        var recents = Defaults[.audienceRecentSets].filter { $0 != token }
        recents.insert(token, at: 0)

        Defaults[.audienceRecentSets] = Array(recents.prefix(storedRecents))
    }
}
