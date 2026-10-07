//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import JellyfinAPI
import SwiftUI

/// About Couchfin: the version, the app-wide options that used to live under the
/// pre-sign-in "Advanced" sheet, and diagnostics. Reachable from Settings and from
/// the couch picker, so there's one place for all of it.
struct AboutAppView: View {

    @Default(.selectUserUseSplashscreen)
    private var selectUserUseSplashscreen
    @Default(.selectUserAllServersSplashscreen)
    private var selectUserAllServersSplashscreen

    @Default(.backgroundSignOutInterval)
    private var backgroundSignOutInterval
    @Default(.signOutOnBackground)
    private var signOutOnBackground
    @Default(.signOutOnClose)
    private var signOutOnClose

    @Router
    private var router

    @StoredValue(.Server.servers)
    private var servers

    /// Presented as its own sheet (from the couch picker) rather than pushed from Settings.
    var isPresentedAsSheet = false

    #if os(tvOS)
    private var selectedServer: ServerState? {
        servers.first { server in
            selectUserAllServersSplashscreen == .server(id: server.id)
        }
    }
    #endif

    private var versionDescription: String {
        "\(UIApplication.appVersion ?? .emptyDash) (\(UIApplication.bundleVersion ?? .emptyDash))"
    }

    var body: some View {
        Form {
            #if os(iOS)
            header
            #endif

            versionSection

            appSection

            diagnosticsSection

            linksSection
        } image: {
            FinView()
                .frame(maxWidth: 520)
        }
        .animation(.linear, value: selectUserUseSplashscreen)
        .animation(.linear, value: signOutOnBackground)
        .navigationTitle(L10n.CouchfinSettings.about)
        .if(isPresentedAsSheet) { view in
            view.navigationBarCloseButton {
                router.dismiss()
            }
        }
    }

    // MARK: - Header

    #if os(iOS)
    @ViewBuilder
    private var header: some View {
        Section {
            VStack(spacing: 14) {
                FinView()
                    .frame(width: 180)
                    .padding(.top, 8)

                Text(L10n.Couchfin.appName)
                    .font(.system(.title, design: .rounded, weight: .heavy))

                Text(versionDescription)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Color.Couchfin.mist)
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
        }
    }
    #endif

    // MARK: - Version

    @ViewBuilder
    private var versionSection: some View {
        Section {
            #if DEBUG
            // swiftlint:disable:next hard_coded_display_string
            LabeledContent(
                "Branch",
                value: UIApplication.gitBranch ?? .emptyDash
            )
            #elseif os(tvOS)
            LabeledContent(
                L10n.version,
                value: versionDescription
            )
            #endif

            #if os(iOS)
            ChevronButton(
                L10n.permissions,
                systemName: "hand.raised.fill"
            ) {
                router.route(to: .appPermissions)
            }
            #endif

            ChevronButton(
                L10n.settings,
                systemName: "gearshape.fill",
                external: true
            ) {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }

                UIApplication.shared.open(url)
            }
        }
    }

    // MARK: - App

    private var serverPicker: some View {
        Picker(L10n.servers, selection: $selectUserAllServersSplashscreen) {
            Label(L10n.random, systemImage: "dice.fill")
                .tag(SelectUserServerSelection.all)

            ForEach(servers.sorted(using: \.name)) { server in
                Text(server.name)
                    .tag(SelectUserServerSelection.server(id: server.id))
            }
        }
    }

    @ViewBuilder
    private var appSection: some View {
        Section {
            Toggle(L10n.useSplashscreen, isOn: $selectUserUseSplashscreen)

            if selectUserUseSplashscreen {
                #if os(tvOS)
                ListRowMenu(L10n.servers) {
                    if selectUserAllServersSplashscreen == .all {
                        Label(L10n.random, systemImage: "dice.fill")
                    } else if let selectedServer {
                        Text(selectedServer.name)
                    } else {
                        Text(L10n.none)
                    }
                } content: {
                    serverPicker
                }
                #else
                serverPicker
                #endif
            }
        } header: {
            Text(L10n.CouchfinSettings.app)
        } footer: {
            if selectUserUseSplashscreen {
                Text(L10n.splashscreenFooter)
            }
        }

        Section {
            Toggle(L10n.signoutClose, isOn: $signOutOnClose)

            Toggle(L10n.signoutBackground, isOn: $signOutOnBackground)

            if signOutOnBackground {
                HourMinutePicker(title: L10n.duration, interval: $backgroundSignOutInterval)
            }
        } footer: {
            Text(L10n.signoutBackgroundFooter)
        }
    }

    // MARK: - Diagnostics

    @ViewBuilder
    private var diagnosticsSection: some View {
        Section(L10n.CouchfinSettings.diagnostics) {
            ChevronButton(L10n.logs) {
                router.route(to: .log)
            }

            if ExperimentalSettingsView.isEnabled {
                ChevronButton(L10n.experimental) {
                    router.route(to: .experimentalSettings)
                }
            }

            #if DEBUG
            ChevronButton("Debug") {
                router.route(to: .debugSettings)
            }
            #endif
        }
    }

    // MARK: - Links

    @ViewBuilder
    private var linksSection: some View {
        // tvOS cannot open generic web links
        #if !os(tvOS)
        Section {
            ChevronButton(
                L10n.sourceCode,
                image: .logoGithub,
                external: true
            ) {
                UIApplication.shared.open(.swiftfinGithub)
            }

            ChevronButton(
                L10n.license,
                content: L10n.mlp2,
                systemName: "text.document",
                external: true
            ) {
                UIApplication.shared.open(.swiftfinGithubLicense)
            }

            ChevronButton(
                L10n.bugsAndFeatures,
                systemName: "plus.circle.fill",
                external: true
            ) {
                UIApplication.shared.open(.swiftfinGithubIssues)
            }
            .symbolRenderingMode(.monochrome)
        } footer: {
            Text(L10n.CouchfinSettings.builtOnSwiftfin)
        }
        #endif
    }
}
