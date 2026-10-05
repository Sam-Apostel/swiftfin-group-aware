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

extension UserState {

    /// The access token stored in the keychain for this user, if any.
    ///
    /// Unlike `accessToken`, this does not `assertionFailure` when the
    /// token is missing. Use this for users other than the current
    /// session user (couch members, household users).
    var storedAccessToken: String? {
        Container.shared.keychainService().get("\(id)-accessToken")
    }

    /// A local, per-device flag marking this user as a kid.
    ///
    /// Kids are treated as restricted when choosing which couch
    /// member the app browses as.
    var isKid: Bool {
        get {
            StoredValues[couchIsKidKey]
        }
        nonmutating set {
            StoredValues[couchIsKidKey] = newValue
        }
    }

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

    private var couchIsKidKey: StoredValues.Key<Bool> {
        StoredValues.Keys.UserKey(
            ownerID: id,
            field: "couchIsKid",
            default: false
        )
    }
}
