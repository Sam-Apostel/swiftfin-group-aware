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

struct SeerrSettingsView: View {

    private enum Field: Hashable {
        case apiKey
        case url
    }

    @Default(.accentColor)
    private var accentColor

    @FocusState
    private var focusedField: Field?

    @InjectedObject(\.seerrService)
    private var seerrService: SeerrService

    @State
    private var apiKey: String = ""
    @State
    private var isDisconnectPresented: Bool = false
    @State
    private var url: String = ""

    @StateObject
    private var viewModel = SeerrSettingsViewModel()

    private var isBusy: Bool {
        viewModel.isConnecting || viewModel.isSigningIn
    }

    private var isConnectDisabled: Bool {
        isBusy || url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// A server is saved, with or without an API key.
    private var hasServer: Bool {
        seerrService.serverURL != nil
    }

    // MARK: - Body

    var body: some View {
        Form(systemImage: "popcorn.fill") {
            serverSection

            connectSection

            if hasServer {
                statusSection

                if viewModel.supportsQuickConnect != false {
                    quickConnectSection
                }

                peopleSection

                disconnectSection
            }
        }
        .navigationTitle(L10n.SeerrSettings.title)
        .topBarTrailing {
            if isBusy {
                ProgressView()
            }
        }
        .onFirstAppear {
            url = seerrService.serverURL?.absoluteString ?? ""
            viewModel.load()

            if !hasServer {
                focusedField = .url
            }
        }
        .confirmationDialog(
            L10n.SeerrSettings.disconnectTitle,
            isPresented: $isDisconnectPresented,
            titleVisibility: .visible
        ) {
            Button(L10n.SeerrSettings.disconnect, role: .destructive) {
                UIDevice.impact(.medium)
                viewModel.disconnect()
                apiKey = ""
            }
        } message: {
            Text(L10n.SeerrSettings.disconnectMessage)
        }
        .errorMessage($viewModel.error)
    }

    // MARK: - Actions

    private func connect() {
        guard !isConnectDisabled else { return }

        focusedField = nil

        Task { @MainActor in
            let didConnect = await viewModel.connect(url: url, apiKey: apiKey)

            // On failure `.errorMessage` already plays the error haptic.
            if didConnect {
                UIDevice.feedback(.success)
                url = seerrService.serverURL?.absoluteString ?? url
                apiKey = ""
            }
        }
    }

    private func signIn(_ person: SeerrSettingsViewModel.Person) {
        Task { @MainActor in
            if await viewModel.signIn(jellyfinUserID: person.id) {
                UIDevice.feedback(.success)
            }
        }
    }

    private func signInEveryone() {
        Task { @MainActor in
            if await viewModel.signInEveryone() {
                UIDevice.feedback(.success)
            }
        }
    }

    // MARK: - Server Section

    @ViewBuilder
    private var serverSection: some View {
        Section(L10n.server) {
            TextField(
                L10n.url,
                text: $url,
                prompt: Text(L10n.SeerrSettings.urlPrompt)
            )
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
            .textContentType(.URL)
            .submitLabel(.next)
            .focused($focusedField, equals: .url)
            .onSubmit {
                focusedField = .apiKey
            }
            .disabled(isBusy)

            SecureField(
                L10n.SeerrSettings.apiKey,
                text: $apiKey,
                maskToggle: .enabled
            ) {
                connect()
            }
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .focused($focusedField, equals: .apiKey)
            .disabled(isBusy)
        } footer: {
            Text(L10n.SeerrQuickConnect.apiKeyOptionalFooter)
        } learnMore: {
            LabeledContent(
                L10n.url,
                value: L10n.SeerrSettings.serverURLDescription
            )
            LabeledContent(
                L10n.SeerrSettings.apiKey,
                value: L10n.SeerrSettings.apiKeyDescription
            )
            LabeledContent(
                L10n.SeerrQuickConnect.title,
                value: L10n.SeerrQuickConnect.description
            )
            LabeledContent(
                L10n.SeerrSettings.asEachPerson,
                value: L10n.SeerrSettings.asEachPersonDescription
            )
        }
    }

    // MARK: - Connect Section

    @ViewBuilder
    private var connectSection: some View {
        Section {
            Button {
                connect()
            } label: {
                ZStack {
                    if viewModel.isConnecting {
                        ProgressView()
                    } else {
                        Text(hasServer ? L10n.SeerrSettings.update : L10n.connect)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .listRowInsets(.zero)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .fontWeight(.semibold)
            .backport
            .buttonStyle(.glassProminent.shadow(false))
            .tint(accentColor)
            .controlSize(.large)
            .frame(maxHeight: 75)
            .disabled(isConnectDisabled)
        }
    }

    // MARK: - Status Section

    @ViewBuilder
    private var statusSection: some View {
        Section(L10n.status) {
            if seerrService.isConfigured {
                Label {
                    if let version = viewModel.version {
                        Text(L10n.SeerrSettings.connectedTo(version))
                    } else {
                        Text(L10n.SeerrSettings.connected)
                    }
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            } else {
                Label {
                    Text(L10n.SeerrQuickConnect.finishSetup)
                } icon: {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                }
            }

            if seerrService.hasAPIKey {
                Label {
                    Text(L10n.SeerrQuickConnect.apiKeySaved)
                } icon: {
                    Image(systemName: "key.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Quick Connect Section

    @ViewBuilder
    private var quickConnectSection: some View {
        Section {
            if viewModel.peopleToSignIn.isEmpty, viewModel.people.isNotEmpty {
                Label {
                    Text(L10n.SeerrQuickConnect.everyoneSignedIn)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            } else {
                Button {
                    signInEveryone()
                } label: {
                    Label {
                        Text(
                            viewModel.peopleToSignIn.count > 1
                                ? L10n.SeerrQuickConnect.signInEveryone
                                : L10n.SeerrQuickConnect.signInWithJellyfin
                        )
                    } icon: {
                        if viewModel.isSigningIn {
                            ProgressView()
                        } else {
                            Image(systemName: "person.badge.key.fill")
                        }
                    }
                }
                .foregroundStyle(accentColor)
                .disabled(isBusy || viewModel.peopleToSignIn.isEmpty)
            }
        } header: {
            Text(L10n.SeerrQuickConnect.title)
        } footer: {
            Text(L10n.SeerrQuickConnect.footer)
        }
    }

    // MARK: - People Section

    @ViewBuilder
    private var peopleSection: some View {
        Section {
            if viewModel.people.isEmpty {
                Text(L10n.SeerrSettings.noPeople)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.people) { person in
                    PersonRow(
                        person: person,
                        server: viewModel.server,
                        quickConnect: quickConnectState(for: person),
                        isDisabled: isBusy,
                        onSignIn: { signIn(person) },
                        onSignOut: { viewModel.signOut(jellyfinUserID: person.id) }
                    )
                }
            }
        } header: {
            Text(L10n.people)
        } footer: {
            Text(L10n.SeerrSettings.peopleFooter)
        }
    }

    private func quickConnectState(for person: SeerrSettingsViewModel.Person) -> PersonRow.QuickConnectState {
        if viewModel.signingInUserIDs.contains(person.id) {
            return .signingIn
        }
        if seerrService.signedInUserIDs.contains(person.id) {
            return .signedIn
        }
        if person.canSignIn, viewModel.supportsQuickConnect != false {
            return .signedOut
        }
        return .unavailable
    }

    // MARK: - Disconnect Section

    @ViewBuilder
    private var disconnectSection: some View {
        Section {
            // Only once someone is signed in: removing the key would otherwise leave Seerr unusable
            if seerrService.hasAPIKey, seerrService.signedInUserIDs.isNotEmpty, viewModel.supportsQuickConnect == true {
                Button(L10n.SeerrQuickConnect.removeAPIKey, role: .destructive) {
                    UIDevice.impact(.light)
                    viewModel.removeAPIKey()
                }
                .frame(maxWidth: .infinity)
                .disabled(isBusy)
            }

            Button(L10n.SeerrSettings.disconnect, role: .destructive) {
                isDisconnectPresented = true
            }
            .frame(maxWidth: .infinity)
            .disabled(isBusy)
        }
    }
}
