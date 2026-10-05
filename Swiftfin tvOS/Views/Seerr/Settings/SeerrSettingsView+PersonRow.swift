//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

extension SeerrSettingsView {

    /// A focusable row for a stored Jellyfin user: avatar, name, their Seerr account and
    /// their Quick Connect session. Pressing it signs them in, or offers to sign them out.
    struct PersonRow: View {

        enum QuickConnectState: Hashable {
            /// Can't sign in from here (no Jellyfin token on this device, or Seerr is too old).
            case unavailable
            case signedOut
            case signingIn
            case signedIn
        }

        @Default(.accentColor)
        private var accentColor

        let person: SeerrSettingsViewModel.Person
        let server: ServerState?
        let quickConnect: QuickConnectState
        let action: () -> Void

        init(
            person: SeerrSettingsViewModel.Person,
            server: ServerState?,
            quickConnect: QuickConnectState,
            action: @escaping () -> Void
        ) {
            self.person = person
            self.server = server
            self.quickConnect = quickConnect
            self.action = action
        }

        private var imageSource: ImageSource {
            guard let server else { return ImageSource() }

            return person.user.profileImageSource(client: server.client)
        }

        /// The Seerr account this person is mapped to.
        private var mappingDescription: String? {
            switch person.mapping {
            case let .mapped(seerrName):
                "→ \(seerrName)"
            case let .imported(seerrName):
                "→ \(L10n.SeerrSettings.imported(seerrName))"
            case .notFound:
                L10n.SeerrSettings.notFound
            case .loading, .unavailable:
                nil
            }
        }

        var body: some View {
            Button(action: action) {
                HStack(spacing: 30) {
                    UserProfileImage(
                        userID: person.user.id,
                        source: imageSource,
                        pipeline: .Swiftfin.local
                    )
                    .frame(width: 60, height: 60)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(person.user.username)
                            .fontWeight(.semibold)
                            .lineLimit(1)

                        if let mappingDescription {
                            Text(mappingDescription)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    quickConnectView
                }
            }
        }

        @ViewBuilder
        private var quickConnectView: some View {
            switch quickConnect {
            case .unavailable:
                Text(L10n.SeerrQuickConnect.notSignedIn)
                    .foregroundStyle(.secondary)

            case .signedOut:
                Text(L10n.SeerrTV.signIn)
                    .fontWeight(.semibold)
                    .foregroundStyle(accentColor)

            case .signingIn:
                ProgressView()

            case .signedIn:
                Label(L10n.SeerrTV.signedIn, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }
}
