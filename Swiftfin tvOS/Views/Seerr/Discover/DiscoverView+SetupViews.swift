//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import FactoryKit
import SwiftUI

extension DiscoverView {

    // MARK: - No Server

    /// No Seerr server on this Apple TV and none (reachable) in the household.
    struct NoServerView: View {

        private enum Action: Hashable {
            case checkAgain
            case enterAddress
        }

        @Default(.accentColor)
        private var accentColor

        @FocusState
        private var focusedAction: Action?

        @Router
        private var router

        @ObservedObject
        var viewModel: SeerrTVSetupViewModel

        /// Adopting the household server failed (unreachable, Seerr older than 3.4, …).
        private var hasAdoptionError: Bool {
            viewModel.adoptionError != nil
        }

        @ViewBuilder
        private var descriptionView: some View {
            if let adoptionError = viewModel.adoptionError {
                VStack(spacing: 10) {
                    Text(adoptionError.localizedDescription)

                    if let attemptedHost = viewModel.attemptedHost {
                        Text(L10n.SeerrTV.triedHost(attemptedHost))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text(L10n.SeerrTV.noServerDescription)
            }
        }

        @ViewBuilder
        private var actionsView: some View {
            HStack(spacing: EdgeInsets.itemSpacing) {
                Button {
                    router.route(to: .seerrSettings)
                } label: {
                    Text(L10n.SeerrTV.enterAddress)
                        .frame(maxWidth: .infinity)
                }
                .fontWeight(.semibold)
                .backport
                .buttonStyle(.glass)
                .frame(width: 400, height: 75)
                .focused($focusedAction, equals: .enterAddress)

                Button {
                    Task {
                        await viewModel.start()
                    }
                } label: {
                    Text(L10n.SeerrTV.checkAgain)
                        .frame(maxWidth: .infinity)
                }
                .fontWeight(.semibold)
                .backport
                .buttonStyle(.glassProminent.shadow(false))
                .tint(accentColor)
                .frame(width: 400, height: 75)
                .focused($focusedAction, equals: .checkAgain)
            }
            .focusSection()
            .defaultFocus($focusedAction, .checkAgain, priority: .userInitiated)
        }

        var body: some View {
            ContentUnavailableView {
                Label(
                    L10n.SeerrDiscover.notConfiguredTitle,
                    systemImage: hasAdoptionError ? "exclamationmark.circle" : "popcorn.fill"
                )
            } description: {
                descriptionView
            } actions: {
                actionsView
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: - Sign In

    /// A server is known, but nobody on this Apple TV has a Seerr session yet:
    /// one press signs the couch in with Jellyfin Quick Connect.
    struct SignInView: View {

        private enum Action: Hashable {
            case signIn
            case settings
        }

        @Default(.accentColor)
        private var accentColor

        @FocusState
        private var focusedAction: Action?

        @Router
        private var router

        @ObservedObject
        var viewModel: SeerrTVSetupViewModel

        /// Who the button signs in: the couch members without a session, else the whole couch.
        private var members: [UserState] {
            let membersToSignIn = viewModel.membersToSignIn

            if membersToSignIn.isNotEmpty {
                return membersToSignIn
            }

            return Container.shared.currentUserSession()?.couch.members ?? []
        }

        private var signingInName: String? {
            if case let .signingIn(name) = viewModel.phase {
                return name
            }

            return nil
        }

        private func signIn() {
            guard signingInName == nil else { return }

            Task {
                await viewModel.signInCouch()
            }
        }

        @ViewBuilder
        private var signInLabel: some View {
            if let signingInName {
                HStack(spacing: 20) {
                    ProgressView()

                    Text(L10n.SeerrTV.signingIn(signingInName))
                }
                .frame(maxWidth: .infinity)
            } else {
                Text(L10n.SeerrTV.signIn)
                    .frame(maxWidth: .infinity)
            }
        }

        @ViewBuilder
        private var buttons: some View {
            VStack(spacing: 30) {
                Button(action: signIn) {
                    signInLabel
                }
                .fontWeight(.semibold)
                .backport
                .buttonStyle(.glassProminent.shadow(false))
                .tint(accentColor)
                .frame(height: 75)
                .focused($focusedAction, equals: .signIn)

                Button {
                    router.route(to: .seerrSettings)
                } label: {
                    Text(L10n.SeerrTV.seerrSettings)
                        .frame(maxWidth: .infinity)
                }
                .fontWeight(.semibold)
                .backport
                .buttonStyle(.glass)
                .frame(height: 75)
                .focused($focusedAction, equals: .settings)
            }
            .frame(maxWidth: 600)
            .focusSection()
            .defaultFocus($focusedAction, .signIn, priority: .userInitiated)
        }

        @ViewBuilder
        private var avatars: some View {
            if let server = viewModel.server, members.isNotEmpty {
                CouchAvatarStack(
                    users: members,
                    server: server,
                    size: 90
                )
            } else {
                Image(systemName: "popcorn.fill")
                    .font(.system(size: 90))
                    .foregroundStyle(.secondary)
            }
        }

        var body: some View {
            VStack(spacing: 40) {
                avatars

                VStack(spacing: 16) {
                    Text(L10n.SeerrTV.signInAs(L10n.SeerrTV.names(members.map(\.username))))
                        .font(.title2)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)

                    Text(L10n.SeerrTV.signInFootnote)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: 900)

                buttons
            }
            .edgePadding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}
