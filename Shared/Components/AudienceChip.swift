//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import JellyfinAPI
import SwiftUI

/// "For Sam & Lisa" with a mini stack of the members' avatars.
///
/// `users` is the list of people the audience is resolved against (usually every
/// stored user on the current server). Ids in `audience` that are not in `users`
/// are counted as "N others".
struct AudienceLabel: View {

    @Injected(\.currentUserSession)
    private var userSession: UserSession?

    private let audience: Set<String>
    private let users: [UserState]

    init(audience: Set<String>, users: [UserState]) {
        self.audience = audience
        self.users = users
    }

    private var members: [UserState] {
        users.filter { audience.contains($0.id) }
    }

    private var avatarSize: CGFloat {
        UIDevice.isTV ? 40 : 22
    }

    @ViewBuilder
    private func avatarStack(client: JellyfinClient) -> some View {
        HStack(spacing: -avatarSize * 0.3) {
            ForEach(Array(members.prefix(4))) { user in
                UserProfileImage(
                    userID: user.id,
                    source: user.profileImageSource(client: client),
                    pipeline: .Swiftfin.local
                )
                .frame(width: avatarSize, height: avatarSize)
            }
        }
        .accessibilityHidden(true)
    }

    var body: some View {
        HStack(spacing: UIDevice.isTV ? 12 : 6) {
            if let client = userSession?.client, members.isNotEmpty {
                avatarStack(client: client)
            }

            Text(Self.sentence(audience: audience, users: users))
                .font(UIDevice.isTV ? .callout : .footnote)
                .fontWeight(.semibold)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

extension AudienceLabel {

    /// "For Sam & Lisa", "For Tuur", "For everyone" or "Pick at least one person".
    static func sentence(audience: Set<String>, users: [UserState]) -> String {
        guard audience.isNotEmpty else {
            return L10n.Audience.pickSomeone
        }

        let userIDs = Set(users.map(\.id))
        let unknownCount = audience.subtracting(userIDs).count

        if users.count > 1, unknownCount == 0, userIDs.isSubset(of: audience) {
            return L10n.Audience.forEveryone
        }

        var names = users
            .filter { audience.contains($0.id) }
            .map(\.username)

        if unknownCount > 0 {
            names.append(L10n.Audience.others(unknownCount))
        }

        let joinedNames = L10n.Audience.joinedNames(names)
        return L10n.Audience.forNames(joinedNames)
    }
}
