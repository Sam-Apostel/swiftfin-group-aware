//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import Logging

// MARK: - Couch

/// Seerr for everyone on the couch: on an Apple TV everyone on the couch is signed in to Jellyfin,
/// so the whole couch can get Seerr sessions (Jellyfin Quick Connect) with one button press.
@MainActor
extension SeerrService {

    /// Couch members, in couch order, that can sign in with Quick Connect from this device
    /// (`quickConnectEligibleUserIDs()`) and have no Seerr session yet (`signedInUserIDs`).
    func couchMembersNeedingSignIn(_ couch: CouchGroup) -> [UserState] {
        let eligibleUserIDs = quickConnectEligibleUserIDs()

        return couch.members.filter { member in
            eligibleUserIDs.contains(member.id) && !signedInUserIDs.contains(member.id)
        }
    }

    /// Signs the members above in one by one. Returns failures by Jellyfin user id; never throws.
    /// Skips members in `hopelessSignInUserIDs` (denied, Quick Connect off, Seerr too old); network failures retry.
    ///
    /// Concurrent sign-ins of the same person share one attempt (`signInWithQuickConnect(jellyfinUserID:)`).
    func signInCouch(_ couch: CouchGroup) async -> [String: Error] {
        var failures: [String: Error] = [:]

        for member in couchMembersNeedingSignIn(couch) {
            guard !Task.isCancelled else { break }

            // Signed in meanwhile (e.g. by a silent sign-in), or denied before: retrying won't help (#55)
            guard !signedInUserIDs.contains(member.id), !hopelessSignInUserIDs.contains(member.id) else { continue }

            do {
                try await signInWithQuickConnect(jellyfinUserID: member.id)
            } catch {
                Logger.swiftfin().error(
                    "Failed to sign a couch member in to Seerr",
                    metadata: [
                        "jellyfinUserID": .string(member.id),
                        "error": .string(error.localizedDescription),
                    ]
                )
                failures[member.id] = error
            }
        }

        return failures
    }

    /// Who a request from this couch is made as.
    ///
    /// - The primary, unless the primary is restricted (a kid, or a parental rating limit).
    /// - Then the first member in couch order that is not restricted and can act on Seerr:
    ///   there is an API key, they are signed in, or they can sign in with Quick Connect.
    /// - Otherwise the primary.
    func requesterJellyfinUserID(for couch: CouchGroup) -> String {
        let primary = couch.primary

        guard primary.isRestricted else { return primary.id }

        let eligibleUserIDs = quickConnectEligibleUserIDs()

        let grownUp = couch.members.first { member in
            guard member.id != primary.id, !member.isRestricted else { return false }

            return hasAPIKey || signedInUserIDs.contains(member.id) || eligibleUserIDs.contains(member.id)
        }

        return grownUp?.id ?? primary.id
    }
}
