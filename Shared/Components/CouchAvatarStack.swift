//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import SwiftUI

/// An overlapping stack of user avatars, for showing everyone on the couch.
///
/// The first user is drawn on top. When there are more users than fit,
/// the last slot shows a "+N" circle.
struct CouchAvatarStack: View {

    private let users: [UserState]
    private let server: ServerState
    private let size: CGFloat
    private let maxVisibleCount = 4

    init(
        users: [UserState],
        server: ServerState,
        size: CGFloat = 28
    ) {
        self.users = users
        self.server = server
        self.size = size
    }

    private var visibleUsers: [UserState] {
        if users.count > maxVisibleCount {
            Array(users.prefix(maxVisibleCount - 1))
        } else {
            users
        }
    }

    private var overflowCount: Int {
        users.count - visibleUsers.count
    }

    private var accessibilityNames: String {
        ListFormatter.localizedString(byJoining: users.map(\.username))
    }

    var body: some View {
        HStack(spacing: -size * 0.4) {
            ForEach(Array(visibleUsers.enumerated()), id: \.element.id) { index, user in
                avatar(for: user)
                    .zIndex(Double(visibleUsers.count - index))
            }

            if overflowCount > 0 {
                overflowView
            }
        }
        // Never dim the avatars because of an edit mode further up the hierarchy
        .isEditing(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityNames)
    }

    private func avatar(for user: UserState) -> some View {
        UserProfileImage(
            userID: user.id,
            source: user.profileImageSource(
                client: server.client
            ),
            pipeline: .Swiftfin.local
        )
        .frame(width: size, height: size)
    }

    private var overflowView: some View {
        Text(L10n.CouchPicker.moreMembers(overflowCount))
            .font(.system(size: size * 0.38, weight: .semibold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .foregroundStyle(.primary)
            .frame(width: size, height: size)
            .background {
                Circle()
                    .fill(.complexSecondary)
            }
            .clipShape(.circle)
            .shadow(radius: 5)
    }
}
