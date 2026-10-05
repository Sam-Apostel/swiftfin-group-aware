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

    /// "Sam → Sam ✓   Signed in": a stored Jellyfin user, the Seerr account they are
    /// mapped to, and their Quick Connect session.
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
        let isDisabled: Bool
        let onSignIn: () -> Void
        let onSignOut: () -> Void

        init(
            person: SeerrSettingsViewModel.Person,
            server: ServerState?,
            quickConnect: QuickConnectState,
            isDisabled: Bool,
            onSignIn: @escaping () -> Void,
            onSignOut: @escaping () -> Void
        ) {
            self.person = person
            self.server = server
            self.quickConnect = quickConnect
            self.isDisabled = isDisabled
            self.onSignIn = onSignIn
            self.onSignOut = onSignOut
        }

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

                VStack(alignment: .leading, spacing: 2) {
                    Text(person.user.username)
                        .fontWeight(.semibold)
                        .lineLimit(1)

                    mappingView
                        .font(.subheadline)
                }

                Spacer(minLength: 8)

                quickConnectView
            }
        }

        // MARK: - Mapping

        @ViewBuilder
        private var mappingView: some View {
            switch person.mapping {
            case .loading:
                ProgressView()
                    .controlSize(.small)

            case let .mapped(seerrName):
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(seerrName)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

            case let .imported(seerrName):
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(L10n.SeerrSettings.imported(seerrName))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

            case .notFound:
                HStack(spacing: 4) {
                    Text(L10n.SeerrSettings.notFound)
                        .foregroundStyle(.secondary)

                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

            case .unavailable:
                Text(L10n.SeerrQuickConnect.notSignedIn)
                    .foregroundStyle(.secondary)
            }
        }

        // MARK: - Quick Connect

        @ViewBuilder
        private var quickConnectView: some View {
            switch quickConnect {
            case .unavailable:
                EmptyView()

            case .signedOut:
                Button(L10n.SeerrQuickConnect.signIn, action: onSignIn)
                    .buttonStyle(.borderless)
                    .fontWeight(.semibold)
                    .foregroundStyle(accentColor)
                    .disabled(isDisabled)

            case .signingIn:
                ProgressView()

            case .signedIn:
                Menu {
                    Button(role: .destructive, action: onSignOut) {
                        Label(L10n.SeerrQuickConnect.signOut, systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } label: {
                    Label(L10n.SeerrQuickConnect.signedIn, systemImage: "person.badge.key.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.subheadline)
                        .foregroundStyle(.green)
                }
                .disabled(isDisabled)
                .accessibilityLabel(L10n.SeerrQuickConnect.signedInWithQuickConnect)
            }
        }
    }
}
