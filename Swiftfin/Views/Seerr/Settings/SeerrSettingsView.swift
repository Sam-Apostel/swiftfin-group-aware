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

    private var isConnectDisabled: Bool {
        viewModel.isConnecting || url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || apiKey.isEmpty
    }

    // MARK: - Body

    var body: some View {
        Form(systemImage: "popcorn.fill") {
            serverSection

            connectSection

            if seerrService.isConfigured {
                statusSection

                peopleSection

                disconnectSection
            }
        }
        .navigationTitle(L10n.SeerrSettings.title)
        .topBarTrailing {
            if viewModel.isConnecting {
                ProgressView()
            }
        }
        .onFirstAppear {
            url = seerrService.serverURL?.absoluteString ?? ""
            viewModel.load()

            if !seerrService.isConfigured {
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

    // MARK: - Connect

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
            .disabled(viewModel.isConnecting)

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
            .disabled(viewModel.isConnecting)
        } footer: {
            Text(L10n.SeerrSettings.apiKeyFooter)
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
                        Text(seerrService.isConfigured ? L10n.SeerrSettings.update : L10n.connect)
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
                        server: viewModel.server
                    )
                }
            }
        } header: {
            Text(L10n.people)
        } footer: {
            Text(L10n.SeerrSettings.peopleFooter)
        }
    }

    // MARK: - Disconnect Section

    @ViewBuilder
    private var disconnectSection: some View {
        Section {
            Button(L10n.SeerrSettings.disconnect, role: .destructive) {
                isDisconnectPresented = true
            }
            .frame(maxWidth: .infinity)
            .disabled(viewModel.isConnecting)
        }
    }
}
