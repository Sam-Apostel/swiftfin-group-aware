//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import Foundation
import JellyfinAPI
import KeychainSwift
import Logging

extension UserState {

    /// The access token stored in the keychain for this user, if any.
    ///
    /// Unlike `accessToken`, this does not `assertionFailure` when the
    /// token is missing. Use this for users other than the current
    /// session user (couch members, household users).
    var storedAccessToken: String? {
        Container.shared.keychainService().get("\(id)-accessToken")
    }

    // MARK: - Kid flag

    /// Whether this user is marked as a kid.
    ///
    /// Cached per device and synced household-wide by `CouchKidsStore`
    /// (`swiftfin-couch-kids`). Setting it is the UI path: it stamps
    /// `kidUpdatedAt` and pushes the change to every account on the server.
    /// Kids are treated as restricted when choosing which couch
    /// member the app browses as.
    var isKid: Bool {
        get {
            StoredValues[couchIsKidKey]
        }
        nonmutating set {
            StoredValues[couchIsKidKey] = newValue
            StoredValues[couchKidUpdatedAtKey] = Int(CouchKidsSync.milliseconds(of: .now))

            let userID = id
            let userServerID = serverID

            Task { @MainActor in
                Container.shared.couchKidsStore().didToggle(userID: userID, serverID: userServerID)
            }
        }
    }

    /// When the kid flag was last decided, on any device. `nil` for a flag that was never set or synced.
    var kidUpdatedAt: Date? {
        let milliseconds = StoredValues[couchKidUpdatedAtKey]

        guard milliseconds > 0 else { return nil }

        return Date(timeIntervalSince1970: Double(milliseconds) / 1000)
    }

    /// Writes a kid flag that came from the household sync, without pushing it again.
    func applySyncedKid(_ isKid: Bool, updatedAt: Date) {
        StoredValues[couchIsKidKey] = isKid
        StoredValues[couchKidUpdatedAtKey] = Int(CouchKidsSync.milliseconds(of: updatedAt))
    }

    // MARK: - Restrictions

    /// Whether this user is a kid or has a maximum parental rating on the server.
    var isRestricted: Bool {
        isKid || data.policy?.maxParentalRating != nil
    }

    /// How restricted this user is: lower is more restricted.
    ///
    /// Kids are always the most restricted (`-1`), otherwise this is the
    /// server's maximum parental rating, or `Int.max` without one.
    var restrictionScore: Int {
        if isKid {
            return -1
        }

        return data.policy?.maxParentalRating ?? Int.max
    }

    /// Whether the server puts no limit at all on what this user can see:
    /// no maximum parental rating, all libraries, and no blocked tags.
    ///
    /// `false` while the policy is unknown (never fetched).
    var hasNoServerAgeLimit: Bool {
        guard let policy = data.policy else { return false }

        return policy.maxParentalRating == nil
            && policy.enableAllFolders != false
            && (policy.blockedTags ?? []).isEmpty
    }

    /// A kid whose server account can still see everything:
    /// only this app's filtering protects them.
    var isKidWithoutServerLimit: Bool {
        isKid && hasNoServerAgeLimit
    }

    /// The parental rating score below which a server age limit makes someone a child.
    ///
    /// Jellyfin 10.11 / 10.12 scores (`Localization/Ratings/*.json`):
    /// - us.json: G 0, TV-Y7 7, PG 10, PG-13 13
    /// - nl.json, be.json, de.json: AL / 0 → 0, 6 → 6, 9 → 9, 12 → 12
    ///
    /// So a limit of PG (10) or 9 is a child, PG-13 (13) or 12 is not.
    static let childRatingScoreLimit = 12

    /// The one rule for who counts as a child on the couch:
    /// marked as a kid, or a server age limit below `childRatingScoreLimit`.
    var isChildAudience: Bool {
        isKid || (data.policy?.maxParentalRating ?? .max) < Self.childRatingScoreLimit
    }

    // MARK: - User data refresh

    /// Fetches the user data of every given user that has a stored token, concurrently,
    /// then applies the results one at a time on the main actor.
    ///
    /// Users without a stored token are skipped, failures are logged and skipped.
    static func refreshUserData(_ users: [UserState], server: ServerState) async {
        var seenIDs: Set<String> = []
        let refreshable = users.filter { user in
            user.serverID == server.id
                && user.storedAccessToken != nil
                && seenIDs.insert(user.id).inserted
        }

        guard refreshable.isNotEmpty else { return }

        await withTaskGroup(of: (UserState, UserDto?, String?).self) { group in
            for user in refreshable {
                group.addTask {
                    do {
                        let userData = try await user.getUserData(server: server)
                        return (user, userData, nil)
                    } catch {
                        return (user, nil, error.localizedDescription)
                    }
                }
            }

            for await (user, userData, errorDescription) in group {
                if let userData {
                    await user.applyUserData(userData)
                } else {
                    Logger.swiftfin().error(
                        "Unable to refresh user information",
                        metadata: [
                            "userID": .string(user.id),
                            "error": .string(errorDescription ?? "unknown error"),
                        ]
                    )
                }
            }
        }
    }

    /// Stores fetched user data: the username and `StoredValues[.User.data(id:)]`.
    ///
    /// Re-reads the stored users when applying, so concurrent refreshes never lose updates.
    /// Does nothing when the user was removed in the meantime.
    @MainActor
    func applyUserData(_ dto: UserDto) {
        var users = StoredValues[.User.users]

        guard let index = users.firstIndex(where: { $0.id == id }) else { return }

        let currentUser = users[index]
        let updatedUsername = dto.name ?? currentUser.username

        if updatedUsername != currentUser.username {
            users[index] = UserState(
                id: currentUser.id,
                serverID: currentUser.serverID,
                username: updatedUsername
            )
            StoredValues[.User.users] = users
        }

        StoredValues[.User.data(id: currentUser.id)] = dto
    }

    // MARK: - Keys

    private var couchIsKidKey: StoredValues.Key<Bool> {
        StoredValues.Keys.UserKey(
            ownerID: id,
            field: "couchIsKid",
            default: false
        )
    }

    /// Milliseconds since 1970, `0` when never set.
    private var couchKidUpdatedAtKey: StoredValues.Key<Int> {
        StoredValues.Keys.UserKey(
            ownerID: id,
            field: "couchKidUpdatedAt",
            default: 0
        )
    }
}
