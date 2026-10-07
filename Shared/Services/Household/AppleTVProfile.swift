//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if os(tvOS)
import Defaults
import FactoryKit
import Foundation
import TVServices

extension Defaults.Keys {

    /// This Apple TV profile's random id. Kept in the profile's own preferences.
    static let appleTVProfileID = Key<String?>("appleTVProfileID", suite: .appSuite)

    /// The Couchfin person this Apple TV profile opens as. Kept in the profile's own preferences.
    static let appleTVDefaultPersonID = Key<String?>("appleTVDefaultPersonID", suite: .appSuite)
}

/// Links each Apple TV profile to one Couchfin person.
///
/// tvOS relaunches the app when someone switches Apple TV profile. On that launch the
/// couch is reset to the profile's default person; any other couch someone picks in the
/// app is kept until the Apple TV profile changes again.
///
/// The default person is set the first time a profile puts someone on the couch, and can
/// be changed in Couch & kids. When the Apple TV isn't set up for several people
/// (`shouldStorePreferencesForCurrentUser` is false), none of this applies.
@MainActor
enum AppleTVProfile {

    /// The profile that ran Couchfin last, shared by every profile.
    private static let lastProfileKeychainKey = "couchfin-last-apple-tv-profile"

    static var isAvailable: Bool {
        TVUserManager().shouldStorePreferencesForCurrentUser
    }

    private static var profileID: String {
        if let id = Defaults[.appleTVProfileID] {
            return id
        }

        let id = UUID().uuidString
        Defaults[.appleTVProfileID] = id
        return id
    }

    /// Call at launch, before the stored session is restored.
    ///
    /// When a different Apple TV profile ran Couchfin last, puts this profile's default
    /// person (alone) on the couch, or shows the couch picker when there's none.
    static func prepareLaunch() {
        guard isAvailable else { return }

        let keychain = Container.shared.keychainService()
        let profileID = profileID
        let lastProfileID = keychain.get(lastProfileKeychainKey)

        keychain.set(profileID, forKey: lastProfileKeychainKey)

        // the first launch with profiles, or the same profile as last time: keep the couch
        guard let lastProfileID, lastProfileID != profileID else { return }

        let users = StoredValues[.User.users]

        if let defaultPersonID = Defaults[.appleTVDefaultPersonID],
           users.contains(where: { $0.id == defaultPersonID })
        {
            Defaults[.Couch.memberIDs] = [defaultPersonID]
            Defaults[.lastSignedInUserID] = .signedIn(userID: defaultPersonID)
        } else {
            Defaults[.Couch.memberIDs] = []
            Defaults[.lastSignedInUserID] = .signedOut
        }
    }

    /// Call when someone starts a couch: the first person this profile picks becomes its default.
    static func didStartCouch(memberIDs: [String]) {
        guard isAvailable, Defaults[.appleTVDefaultPersonID] == nil, let first = memberIDs.first else { return }

        Defaults[.appleTVDefaultPersonID] = first
    }
}
#endif
