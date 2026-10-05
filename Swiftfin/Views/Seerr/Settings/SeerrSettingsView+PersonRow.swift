//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension SeerrSettingsView {

    /// "Sam → Sam ✓": a stored Jellyfin user and the Seerr account they are mapped to.
    struct PersonRow: View {

        let person: SeerrSettingsViewModel.Person
        let server: ServerState?

        private var imageSource: ImageSource {
            guard let server else { return ImageSource() }

            return person.user.profileImageSource(client: server.client)
        }

        var body: some View {
            HStack(spacing: 12) {
                UserProfileImage(
                    userID: person.user.id,
                    source: imageSource,
                    pipeline: .Swiftfin.local
                )
                .frame(width: 32, height: 32)

                Text(person.user.username)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                Spacer(minLength: 8)

                mappingView
            }
        }

        @ViewBuilder
        private var mappingView: some View {
            switch person.mapping {
            case .loading:
                ProgressView()

            case let .mapped(seerrName):
                HStack(spacing: 6) {
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(seerrName)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }

            case .notFound:
                HStack(spacing: 6) {
                    Text(L10n.SeerrSettings.notFound)
                        .foregroundStyle(.secondary)

                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}
