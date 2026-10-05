//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Foundation
import JellyfinAPI
import SwiftUI

struct QuickConnectAuthorizeView: View {

    @Default(.accentColor)
    private var accentColor

    @Environment(\.localUserAuthenticationAction)
    private var authenticationAction

    @Router
    private var router

    @FocusState
    private var isCodeFocused: Bool

    @StateObject
    private var viewModel: QuickConnectAuthorizeViewModel

    @State
    private var code: String = ""
    @State
    private var isPresentingSuccess: Bool = false
    /// Waiting for the chosen person's PIN or Face ID.
    @State
    private var isConfirmingPerson: Bool = false

    init(user: UserDto) {
        self._viewModel = StateObject(wrappedValue: QuickConnectAuthorizeViewModel(user: user))
    }

    /// Signing another device in as someone else hands out their account: someone whose profile
    /// is locked on this phone confirms with their PIN or Face ID first, like on the couch picker.
    private func authorize() {
        guard let person = viewModel.chosenPersonNeedingConfirmation else {
            viewModel.authorize(code: code)
            return
        }

        let code = code
        let authenticationAction = authenticationAction

        isConfirmingPerson = true

        Task { @MainActor in
            defer { isConfirmingPerson = false }

            do {
                try await Self.confirm(person, authenticationAction: authenticationAction)
                viewModel.authorize(code: code)
            } catch is CancellationError {
                isCodeFocused = true
            } catch {
                viewModel.error = error
            }
        }
    }

    /// Throws when the person's PIN or Face ID didn't check out. Fails closed without an authentication action.
    @MainActor
    private static func confirm(
        _ person: UserState,
        authenticationAction: LocalUserAuthenticationAction?
    ) async throws {
        guard let authenticationAction else {
            throw ErrorMessage(L10n.deviceAuthFailed)
        }

        let policy = person.accessPolicy
        let evaluated = try await authenticationAction(
            policy: policy,
            reason: policy.authenticateReason(user: person)
        )

        if let pinPolicy = evaluated as? PinEvaluatedUserAccessPolicy,
           !CouchMemberAuthenticator.isValidPin(pinPolicy.pin, for: person)
        {
            throw ErrorMessage(L10n.invalidPin)
        }
    }

    @ViewBuilder
    private var loginUserRow: some View {
        HStack {
            if let userSession = viewModel.userSession {
                UserProfileImage(
                    userID: viewModel.user.id,
                    source: viewModel.user.profileImageSource(
                        client: userSession.client,
                        maxWidth: 120
                    )
                )
                .frame(width: 50, height: 50)
            }

            Text(viewModel.user.name ?? L10n.unknown)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// "Sign in as": one avatar per account on this device, the chosen one checked.
    @ViewBuilder
    private var personChooser: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: EdgeInsets.itemSpacing) {
                ForEach(viewModel.householdSessions, id: \.user.id) { session in
                    AudiencePickerView.MemberButton(
                        user: session.user,
                        client: session.client,
                        isKid: session.user.isChildAudience,
                        isSelected: session.user.id == viewModel.chosenUserID
                    ) {
                        viewModel.select(session: session)
                    }
                    .frame(width: 76)
                }
            }
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
        .disabled(viewModel.state == .authorizing || isConfirmingPerson)
    }

    @ViewBuilder
    private var userSection: some View {
        if viewModel.isChoosingPerson {
            Section {
                personChooser
            } header: {
                Text(L10n.TVSetup.signInAs)
            } footer: {
                Text(L10n.TVSetup.signInAsFooter(viewModel.user.name ?? L10n.unknown))
            }
        } else {
            Section {
                loginUserRow
            } header: {
                Text(L10n.user)
            } footer: {
                Text(L10n.quickConnectUserDisclaimer)
            }
        }
    }

    var body: some View {
        Form {
            userSection

            Section {
                TextField(L10n.quickConnectCode, text: $code)
                    .keyboardType(.numberPad)
                    .disabled(viewModel.state == .authorizing)
                    .focused($isCodeFocused)
            } footer: {
                Text(L10n.quickConnectCodeInstruction)
            }

            if viewModel.state == .authorizing {
                Button(role: .cancel) {
                    viewModel.cancel()
                    isCodeFocused = true
                } label: {
                    Text(L10n.cancel)
                        .frame(maxWidth: .infinity)
                }
                .listRowInsets(.zero)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .fontWeight(.semibold)
                .backport
                .buttonStyle(.glassProminent.shadow(false))
                #if os(iOS)
                .controlSize(.large)
                #endif
            } else {
                Button(action: authorize) {
                    Text(L10n.authorize)
                        .frame(maxWidth: .infinity)
                }
                .listRowInsets(.zero)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .fontWeight(.semibold)
                .backport
                .buttonStyle(.glassProminent.shadow(false))
                .tint(accentColor)
                #if os(iOS)
                .controlSize(.large)
                #endif
                .disabled(code.count != 6 || viewModel.state == .authorizing || isConfirmingPerson)
            }
        }
        .interactiveDismissDisabled(viewModel.state == .authorizing)
        .navigationBarBackButtonHidden(viewModel.state == .authorizing)
        .navigationTitle(L10n.quickConnect)
        .onFirstAppear {
            isCodeFocused = true
        }
        .onChange(of: code) {
            code = String(code.prefix(6))
        }
        .onReceive(viewModel.$error) { error in
            guard error != nil else { return }

            UIDevice.feedback(.error)
        }
        .onReceive(viewModel.events) { event in
            switch event {
            case .authorized:
                UIDevice.feedback(.success)
                isPresentingSuccess = true
            }
        }
        .topBarTrailing {
            if viewModel.state == .authorizing {
                ProgressView()
            }
        }
        .alert(
            L10n.quickConnect,
            isPresented: $isPresentingSuccess
        ) {
            Button(L10n.dismiss, role: .cancel) {
                router.dismiss()
            }
        } message: {
            Text(L10n.quickConnectSuccessMessage)
        }
        .errorMessage($viewModel.error) {
            isCodeFocused = true
        }
    }
}
