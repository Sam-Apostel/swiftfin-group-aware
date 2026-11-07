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

struct UniverseSettingsView: View {

    @Default(.universesThemed)
    private var isThemed

    @InjectedObject(\.universeService)
    private var service: UniverseService

    @State
    private var url = ""
    @State
    private var isBusy = false
    @State
    private var error: Error?
    @State
    private var notice: String?

    private var isAdministrator: Bool {
        Container.shared.currentUserSession()?.user.data.policy?.isAdministrator == true
    }

    var body: some View {
        Form(systemImage: "globe.americas.fill") {
            Section {
                TextField(L10n.url, text: $url, prompt: Text(L10n.Universes.urlPrompt))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .disabled(isBusy)

                Button(L10n.Universes.connect) {
                    connect()
                }
                .disabled(isBusy || url.trimmingCharacters(in: .whitespaces).isEmpty)

                Button(L10n.Universes.findAutomatically) {
                    service.rediscover()
                }
                .disabled(isBusy || service.isDiscovering)
            } header: {
                Text(L10n.server)
            } footer: {
                Text(L10n.Universes.settingsFooter)
            }

            if service.isConfigured {
                Section(L10n.status) {
                    if let status = service.status {
                        LabeledContent(L10n.Universes.universesCount, value: String(status.counts.universes))
                        LabeledContent(L10n.Universes.reviewsCount, value: String(status.counts.reviews))

                        if status.scan.state == "running" {
                            LabeledContent(L10n.Universes.lastScan, value: status.scan.step ?? L10n.Universes.scanning)
                        } else if let date = status.lastScan?.date {
                            LabeledContent(L10n.Universes.lastScan, value: date.formatted(date: .abbreviated, time: .shortened))
                        }
                    }

                    if isAdministrator {
                        Button(L10n.Universes.scanNow) {
                            scan()
                        }
                        .disabled(isBusy || service.status?.scan.state == "running")
                    }

                    Button(L10n.Universes.disconnect, role: .destructive) {
                        service.disconnect()
                        url = ""
                    }
                }
            } else if service.isDiscovering {
                Section {
                    ProgressView()
                }
            }

            Section {
                Toggle(L10n.Universes.theme, isOn: $isThemed)
            } footer: {
                Text(L10n.Universes.themeFooter)
            }
        }
        .navigationTitle(L10n.Universes.settingsTitle)
        .topBarTrailing {
            if isBusy || service.isDiscovering {
                ProgressView()
            }
        }
        .onFirstAppear {
            url = service.serverURL?.absoluteString ?? ""
        }
        .onChange(of: service.serverURL) {
            url = service.serverURL?.absoluteString ?? url
        }
        .task {
            await service.refreshOverview(force: true)
        }
        .errorMessage($error)
        .alert(
            notice ?? "",
            isPresented: isNoticePresented
        ) {
            Button(L10n.dismiss, role: .cancel) {}
        }
    }

    private var isNoticePresented: Binding<Bool> {
        Binding(
            get: { notice != nil },
            set: { isPresented in
                if !isPresented {
                    notice = nil
                }
            }
        )
    }

    private func connect() {
        var text = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.contains("://") {
            text = "http://" + text
        }
        guard let url = URL(string: text), url.host() != nil else {
            error = ErrorMessage(L10n.Universes.notFound)
            return
        }

        isBusy = true
        Task { @MainActor in
            defer { isBusy = false }
            do {
                try await service.configure(url: url)
                UIDevice.feedback(.success)
            } catch {
                self.error = error
            }
        }
    }

    private func scan() {
        isBusy = true
        Task { @MainActor in
            defer { isBusy = false }
            do {
                try await service.scan()
                notice = L10n.Universes.scanStarted
            } catch {
                self.error = error
            }
        }
    }
}
