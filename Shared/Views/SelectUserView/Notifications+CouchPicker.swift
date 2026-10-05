//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

extension Notifications.Key {

    /// Posted by `UserSignInView` after a user signed in and was saved on this device:
    /// a new user, or an existing user whose stored access token was just replaced.
    ///
    /// Signing in never starts a session by itself. The "Who's on the couch?" picker
    /// puts the user on the couch, and a signed-in couch can rebuild its member sessions.
    ///
    /// - Payload: The saved user.
    static var didAddUser: Key<UserState> {
        Key("didAddUser")
    }
}
