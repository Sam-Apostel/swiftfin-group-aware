//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

struct SettingsBarButton: View {

    let server: ServerState
    let user: UserState
    let couch: CouchGroup?
    let action: () -> Void

    init(
        server: ServerState,
        user: UserState,
        couch: CouchGroup? = nil,
        action: @escaping () -> Void
    ) {
        self.server = server
        self.user = user
        self.couch = couch
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            if let couch, couch.isGroup {
                CouchAvatarStack(
                    users: couch.members,
                    server: server,
                    size: 28
                )
            } else {
                AlternateLayoutView {
                    // Seems necessary for button layout
                    Image(systemName: "gearshape.fill")
                } content: {
                    UserProfileImage(
                        userID: user.id,
                        source: user.profileImageSource(
                            client: server.client
                        ),
                        pipeline: .Swiftfin.local
                    )
                }
            }
        }
        .accessibilityLabel(L10n.settings)
    }
}
