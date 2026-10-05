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

/// Seerr settings on Apple TV: pick the household's server or enter an address, and sign people in
/// with Jellyfin Quick Connect. There is no API key here: it stays on the iPhone.
struct SeerrSettingsView: View {

    @Default(.accentColor)
    private var accentColor

    @InjectedObject(\.seerrService)
    private var seerrService: SeerrService

    @State
    private var householdURL: URL?
    @State
    private var isDisconnectPresented: Bool = false
    @State
    private var signOutPerson: SeerrSettingsViewModel.Person?
    @State
    private var url: String = ""

    @StateObject
    private var viewModel = SeerrSettingsViewModel()

    init() {}

    private var isBusy: Bool {
        viewModel.isConnecting || viewModel.isSigningIn
    }

    /// A server is saved, whether or not anyone is signed in yet.
    private var hasServer: Bool {
        seerrService.serverURL != nil
    }

    private var isConnectDisabled: Bool {
        isBusy || url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var currentHost: String {
        guard let serverURL = seerrService.serverURL else {
            return L10n.SeerrSettings.notConnected
        }

        return serverURL.host() ?? serverURL.absoluteString
    }

    /// The household's server, when this Apple TV uses another one (or none).
    private var householdSuggestion: URL? {
        guard let householdURL else { return nil }

        let household = SeerrClient.serverURL(from: householdURL.absoluteString)?.absoluteString
        let current = seerrService.serverURL.flatMap { SeerrClient.serverURL(from: $0.absoluteString) }?.absoluteString

        return household == current ? nil : householdURL
    }

    // MARK: - Body

    var body: some View {
        Form(systemImage: "popcorn.fill") {
            serverSection

            addressSection

            connectSection

            if hasServer {
                peopleSection

                disconnectSection
            }
        }
        .navigationTitle(L10n.SeerrSettings.title)
        .onFirstAppear {
            url = seerrService.serverURL?.absoluteString ?? ""
            viewModel.load()
        }
        .task {
            householdURL = await seerrService.householdServerURL()
        }
        .alert(
            L10n.SeerrSettings.disconnectTitle,
            isPresented: $isDisconnectPresented
        ) {
            Button(L10n.SeerrSettings.disconnect, role: .destructive) {
                // Discover no longer signs the couch in by itself
                SeerrTVSetupFlags.noteExplicitSignOut()
                viewModel.disconnect()
                url = ""
            }

            Button(L10n.cancel, role: .cancel) {}
        } message: {
            Text(L10n.SeerrSettings.disconnectMessage)
        }
        .alert(
            L10n.SeerrTV.signOutTitle(signOutPerson?.user.username ?? ""),
            isPresented: isSignOutPresented
        ) {
            Button(L10n.SeerrTV.signOut, role: .destructive) {
                if let signOutPerson {
                    SeerrTVSetupFlags.noteExplicitSignOut()
                    viewModel.signOut(jellyfinUserID: signOutPerson.id)
                }
                signOutPerson = nil
            }

            Button(L10n.cancel, role: .cancel) {
                signOutPerson = nil
            }
        }
        .errorMessage($viewModel.error)
    }

    private var isSignOutPresented: Binding<Bool> {
        Binding(
            get: { signOutPerson != nil },
            set: { isPresented in
                if !isPresented {
                    signOutPerson = nil
                }
            }
        )
    }

    // MARK: - Actions

    private func connect(to address: String) {
        guard !isBusy else { return }

        Task { @MainActor in
            // No API key on Apple TV: the server is saved for Quick Connect
            let didConnect = await viewModel.connect(url: address, apiKey: "")

            if didConnect {
                SeerrTVSetupFlags.clearExplicitSignOut()
                url = seerrService.serverURL?.absoluteString ?? address
            }
        }
    }

    private func personAction(_ person: SeerrSettingsViewModel.Person) {
        switch quickConnectState(for: person) {
        case .signedOut:
            // A manual sign-in: Discover may sign the couch in by itself again
            SeerrTVSetupFlags.clearExplicitSignOut()

            Task { @MainActor in
                await viewModel.signIn(jellyfinUserID: person.id)
            }

        case .signedIn:
            signOutPerson = person

        case .signingIn, .unavailable:
            break
        }
    }

    private func signInEveryone() {
        SeerrTVSetupFlags.clearExplicitSignOut()

        Task { @MainActor in
            _ = await viewModel.signInEveryone()
        }
    }

    // MARK: - Server Section

    @ViewBuilder
    private var serverSection: some View {
        Section {
            LabeledContent(L10n.SeerrTV.currentServer, value: currentHost)

            if seerrService.isConfigured, let version = viewModel.version {
                LabeledContent(L10n.status, value: L10n.SeerrSettings.connectedTo(version))
            }

            if let householdSuggestion {
                Button {
                    connect(to: householdSuggestion.absoluteString)
                } label: {
                    Label(
                        L10n.SeerrTV.useHouseholdServer(householdSuggestion.host() ?? householdSuggestion.absoluteString),
                        systemImage: "house.fill"
                    )
                }
                .disabled(isBusy)
            }
        } header: {
            Text(L10n.server)
        } footer: {
            Text(L10n.SeerrTV.apiKeyFooter)
        }
    }

    // MARK: - Address Section

    @ViewBuilder
    private var addressSection: some View {
        Section(L10n.SeerrTV.enterAddress) {
            TextField(
                L10n.url,
                text: $url,
                prompt: Text(L10n.SeerrSettings.urlPrompt)
            )
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
            .disabled(isBusy)
        }
    }

    @ViewBuilder
    private var connectSection: some View {
        Section {
            Button {
                connect(to: url)
            } label: {
                ZStack {
                    if viewModel.isConnecting {
                        ProgressView()
                    } else {
                        Text(L10n.SeerrTV.connectAddress)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .listRowInsets(.zero)
            .listRowBackground(Color.clear)
            .fontWeight(.semibold)
            .backport
            .buttonStyle(.glassProminent.shadow(false))
            .tint(accentColor)
            .frame(maxHeight: 75)
            .disabled(isConnectDisabled)
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
                        quickConnect: quickConnectState(for: person)
                    ) {
                        personAction(person)
                    }
                }

                if viewModel.supportsQuickConnect != false, viewModel.peopleToSignIn.isNotEmpty {
                    Button {
                        signInEveryone()
                    } label: {
                        Label(L10n.SeerrTV.signInEveryone, systemImage: "person.badge.key.fill")
                    }
                    .disabled(isBusy)
                }
            }
        } header: {
            Text(L10n.people)
        } footer: {
            Text(L10n.SeerrQuickConnect.footer)
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
            Button(L10n.SeerrSettings.disconnect, role: .destructive) {
                isDisconnectPresented = true
            }
            .frame(maxWidth: .infinity)
            .disabled(isBusy)
        }
    }
}
