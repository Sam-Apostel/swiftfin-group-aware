//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CollectionVGrid
import Defaults
import FactoryKit
import JellyfinAPI
import SwiftUI

struct UserSignInView: View {

    private enum Field: Hashable {
        case username
        case password
    }

    @Environment(\.localUserAuthenticationAction)
    private var authenticationAction

    @FocusState
    private var focusedTextField: Field?

    @Router
    private var router

    @State
    private var accessPolicy: LocalUserAccessPolicy = .none
    /// Marks the user as a kid when saved. Only ever sets the flag, never unsets it.
    @State
    private var isKid: Bool = false
    @State
    private var password: String = ""
    @State
    private var pinHint: String = ""
    @State
    private var username: String = ""

    @StateObject
    private var viewModel: UserSignInViewModel

    /// - Parameter username: Fills in the username, e.g. to sign a stored user in again.
    init(server: ServerState, username: String? = nil) {
        self._viewModel = StateObject(wrappedValue: UserSignInViewModel(server: server))
        self._username = State(initialValue: username ?? "")
    }

    private func handleEvent(_ event: UserSignInViewModel._Event) {
        switch event {
        case let .connected(user):
            guard let authenticationAction else { return }

            viewModel.save(
                user: user,
                authenticationAction: (
                    authenticationAction,
                    accessPolicy,
                    accessPolicy.createReason(
                        user: user.state.state
                    )
                ),
                evaluatedPolicyMap: .init(action: processEvaluatedPolicy)
            )

        case let .existingUser(existingUser):
            guard let authenticationAction else { return }

            // Someone who just typed the password never wants to keep the old,
            // possibly revoked token: always replace it. The user's own local
            // PIN or device check still runs.
            let userState = existingUser.state.state
            let existingUserAccessPolicy = userState.accessPolicy

            viewModel.saveExisting(
                user: existingUser,
                replaceForAccessToken: true,
                authenticationAction: (
                    authenticationAction,
                    existingUserAccessPolicy,
                    existingUserAccessPolicy.authenticateReason(
                        user: userState
                    )
                ),
                evaluatedPolicyMap: .init(action: processEvaluatedPolicy)
            )

        case let .saved(user):
            // Only ever sets the kid flag, never unsets it
            if isKid {
                user.isKid = true
            }

            // Signing in never starts a session: the couch picker (or a signed-in
            // couch) picks the user up from this notification.
            Notifications[.didAddUser].post(user)
            UIDevice.feedback(.success)
            router.dismiss()
        }
    }

    private func processEvaluatedPolicy(
        _ evaluatedPolicy: any EvaluatedLocalUserAccessPolicy
    ) -> any EvaluatedLocalUserAccessPolicy {
        if let pinPolicy = evaluatedPolicy as? PinEvaluatedUserAccessPolicy {
            return PinEvaluatedUserAccessPolicy(
                pin: pinPolicy.pin,
                pinHint: pinHint
            )
        }

        return evaluatedPolicy
    }

    @ViewBuilder
    private func disclaimerText(_ disclaimer: String) -> some View {
        if let attributedString = try? AttributedString(
            markdown: disclaimer,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributedString)
        } else {
            Text(disclaimer)
        }
    }

    // MARK: - Sign In Section

    @ViewBuilder
    private var signInSection: some View {
        Section {
            TextField(L10n.username, text: $username)
                .autocorrectionDisabled()
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .focused($focusedTextField, equals: .username)
                .onSubmit {
                    focusedTextField = .password
                }

            SecureField(
                L10n.password,
                text: $password,
                maskToggle: .enabled
            ) {
                focusedTextField = nil

                viewModel.signIn(
                    username: username,
                    password: password
                )
            }
            .autocorrectionDisabled()
            .textContentType(.password)
            .textInputAutocapitalization(.never)
            .focused($focusedTextField, equals: .password)

            Toggle(isOn: $isKid) {
                Label(L10n.CouchPicker.thisIsAKid, systemImage: "figure.child")
            }
            .disabled(viewModel.state == .signingIn)
        } header: {
            Text(L10n.signInToServer(viewModel.server.name))
        } footer: {
            switch accessPolicy {
            case .requireDeviceAuthentication:
                Label(L10n.userDeviceAuthRequiredDescription, systemImage: "exclamationmark.circle.fill")
                    .labelStyle(.sectionFooterWithImage(imageStyle: .orange))

            case .requirePin:
                Label(L10n.userPinRequiredDescription, systemImage: "exclamationmark.circle.fill")
                    .labelStyle(.sectionFooterWithImage(imageStyle: .orange))

            case .none:
                EmptyView()
            }
        }

        if case .signingIn = viewModel.state {
            Button(role: .cancel) {
                viewModel.cancel()
            } label: {
                Text(L10n.cancel)
                    .frame(maxWidth: .infinity)
            }
            .listRowInsets(.zero)
            .listRowBackground(Color.clear)
            .fontWeight(.semibold)
            .backport
            .buttonStyle(.glassProminent.shadow(false))
            #if os(iOS)
            .controlSize(.large)
            #endif
            #if os(iOS)
            .listRowSeparator(.hidden)
            #endif
            .frame(maxHeight: 75)
        } else {
            Button {
                viewModel.signIn(
                    username: username,
                    password: password
                )
            } label: {
                Text(L10n.signIn)
                    .frame(maxWidth: .infinity)
            }
            .listRowInsets(.zero)
            .listRowBackground(Color.clear)
            .fontWeight(.semibold)
            .backport
            .buttonStyle(.glassProminent.shadow(false))
            .tint(.jellyfinPurple)
            #if os(iOS)
            .controlSize(.large)
            .listRowSeparator(.hidden)
            #endif
            .frame(maxHeight: 75)
            .disabled(username.isEmpty)
        }

        if viewModel.isQuickConnectEnabled {
            Section {
                Button {
                    router.route(
                        to: .quickConnect(
                            client: viewModel.server.client
                        ) { secret in
                            await viewModel.signInQuickConnect(secret: secret)
                        }
                    )
                } label: {
                    Text(L10n.quickConnect)
                        .frame(maxWidth: .infinity)
                }
                .listRowInsets(.zero)
                .listRowBackground(Color.clear)
                .fontWeight(.semibold)
                .backport
                .buttonStyle(.glassProminent.shadow(false))
                .tint(.jellyfinPurple)
                #if os(iOS)
                .controlSize(.large)
                #endif
                #if os(iOS)
                .listRowSeparator(.hidden)
                #endif
                .disabled(viewModel.state == .signingIn)
            }
        }

        if let disclaimer = viewModel.serverDisclaimer {
            Section(L10n.disclaimer) {
                disclaimerText(disclaimer)
                    .font(.callout)
            }
        }
    }

    // MARK: - Public Users Section

    @ViewBuilder
    private var publicUsersSection: some View {
        Section(L10n.publicUsers) {
            if viewModel.publicUsers.isEmpty {
                Text(L10n.noPublicUsers)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                #if os(iOS)
                ForEach(viewModel.publicUsers) { user in
                    ChevronButton {
                        username = user.name ?? ""
                        password = ""
                        focusedTextField = .password
                    } label: {
                        HStack {
                            UserProfileImage(
                                userID: user.id,
                                source: user.profileImageSource(
                                    client: viewModel.server.client,
                                    maxWidth: 50
                                )
                            )
                            .frame(width: 50, height: 50)

                            Text(user.name ?? .emptyDash)
                                .fontWeight(.semibold)
                                .lineLimit(1)
                        }
                    }
                }
                #else
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: EdgeInsets.itemSpacing),
                        count: 4
                    ),
                    spacing: EdgeInsets.itemSpacing
                ) {
                    ForEach(viewModel.publicUsers) { user in
                        UserButton(
                            user: user,
                            client: viewModel.server.client
                        ) {
                            username = user.name ?? ""
                            password = ""
                            focusedTextField = .password
                        }
                        .withViewContext(.isOverComplexContent)
                    }
                }
                #endif
            }
        }
        .disabled(viewModel.state == .signingIn)
    }

    @ViewBuilder
    private var contentView: some View {
        #if os(iOS)
        List {
            signInSection
            publicUsersSection
        }
        .toolbarTitleDisplayMode(.inline)
        .navigationBarCloseButton(disabled: viewModel.state == .signingIn) {
            router.dismiss()
        }
        .topBarTrailing {
            if viewModel.state == .signingIn || viewModel.background.is(.gettingPublicData) {
                ProgressView()
            }

            Button(L10n.security, systemImage: "gearshape.fill") {
                router.route(
                    to: .userSecurity(
                        pinHint: $pinHint,
                        accessPolicy: $accessPolicy
                    )
                )
            }
        }
        #else
        SplitLoginWindowView(
            isLoading: viewModel.state == .signingIn,
            backgroundImageSource: viewModel.server.splashScreenImageSource
        ) {
            signInSection
        } trailingContentView: {
            publicUsersSection
        }
        #endif
    }

    // MARK: - Body

    var body: some View {
        contentView
            .navigationTitle(L10n.signIn.localizedCapitalized)
            .interactiveDismissDisabled(viewModel.state == .signingIn)
            .onReceive(viewModel.events, perform: handleEvent)
            .onFirstAppear {
                // A prefilled username (signing in again) only needs the password
                focusedTextField = username.isEmpty ? .username : .password
                viewModel.getPublicData()
            }
            .errorMessage($viewModel.error)
    }
}
