//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import FactoryKit
import JellyfinAPI
import SwiftUI

struct SettingsView: View {

    #if os(iOS)
    @Default(.userAppearance)
    private var appearance
    #endif

    @Default(.userAccentColor)
    private var accentColor
    @Default(.Couch.lastMemberIDs)
    private var lastCouchMemberIDs

    @InjectedObject(\.userSessionManager)
    private var userSessionManager: UserSessionManager

    @Router
    private var router

    @InjectedObject(\.seerrService)
    private var seerrService: SeerrService

    // MARK: - Body

    var body: some View {
        Form(image: .jellyfinBlobBlue) {
            couchSection
            serverSection
            requestsSection
            customizeSection
            diagnosticsSection
        }
        #if os(iOS)
        .navigationTitle(L10n.settings)
            .navigationBarCloseButton {
                router.dismiss()
            }
        #endif
    }

    // MARK: - Couch Section

    @ViewBuilder
    private var couchSection: some View {
        if let userSession = userSessionManager.currentSession {
            Section {
                couchMembersRow(
                    couch: userSession.couch,
                    server: userSession.server
                )

                ChevronButton(
                    L10n.CouchSettings.couchSettings,
                    systemName: "sofa.fill"
                ) {
                    router.route(to: .couchSettings)
                }
            } header: {
                Text(L10n.Couch.title)
            }
        }

        Section {
            Button {
                Task { @MainActor in
                    UIDevice.impact(.medium)
                    await userSessionManager.signOut(reason: .explicit)
                    router.dismiss()
                }
            } label: {
                Text(L10n.CouchSwitcher.switchUserOrServer)
                    .frame(maxWidth: .infinity)
                    // Otherwise non-Liquid Glass only uses text height
                    .if(!UIDevice.supportsLiquidGlass) { button in
                        button
                            .frame(maxHeight: .infinity)
                    }
            }
            .listRowInsets(.zero)
            .listRowBackground(Color.clear)
            #if os(iOS)
            .listRowSeparator(.hidden)
            #endif
            .fontWeight(.semibold)
            .backport
            .buttonStyle(.glassProminent.shadow(false))
            .tint(accentColor)
            #if os(iOS)
            .controlSize(.large)
            #endif
            .accessibilityHint(L10n.CouchSwitcher.switchUserOrServerHint)
        }
    }

    /// Opens the couch switcher: add people or take them off without signing anyone out.
    /// One focus stop on tvOS ("Couch settings" is the next row).
    @ViewBuilder
    private func couchMembersRow(couch: CouchGroup, server: ServerState) -> some View {
        ChevronButton(action: { router.route(to: .couchSwitcher) }) {
            couchMembersLabel(couch: couch, server: server)
        }
        .accessibilityHint(L10n.CouchSwitcher.changeWhosOnTheCouch)
    }

    @ViewBuilder
    private func couchMembersLabel(couch: CouchGroup, server: ServerState) -> some View {
        HStack(spacing: UIDevice.isTV ? 30 : 12) {
            CouchAvatarStack(
                users: couch.members,
                server: server,
                size: UIDevice.isTV ? 60 : 40
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.CouchSettings.onTheCouch(couch.displayNames))
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if let browsingAs = browsingAsDescription(couch: couch) {
                    Text(browsingAs)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// "Browsing as Tuur (kid-safe)" when kid-safe browsing made a restricted
    /// member the primary instead of the first person picked.
    private func browsingAsDescription(couch: CouchGroup) -> String? {
        guard couch.isGroup, couch.primary.isRestricted else { return nil }

        let firstPickID = lastCouchMemberIDs.first { couch.memberIDs.contains($0) }

        if let firstPickID, firstPickID == couch.primary.id {
            return nil
        }

        return L10n.CouchSettings.browsingAsKidSafe(couch.primary.username)
    }

    // MARK: - Server Section

    @ViewBuilder
    private var serverSection: some View {
        if let userSession = userSessionManager.currentSession {
            Section {
                UserProfileRow(user: userSession.user.data) {
                    router.route(to: .localUserSettings(user: userSession.user.data))
                }

                ChevronButton(
                    L10n.server,
                    action: {
                        router.route(to: .editLocalServer(server: userSession.server))
                    }
                ) {
                    Label {
                        Text(userSession.server.name)
                    } icon: {
                        if !userSession.server.isVersionCompatible {
                            Image(systemName: "exclamationmark.circle.fill")
                        }
                    }
                    .labelStyle(.sectionFooterWithImage(imageStyle: .orange))
                }

                #if os(iOS)
                if userSession.user.data.policy?.isAdministrator == true {
                    ChevronButton(L10n.dashboard) {
                        router.route(to: .adminDashboard)
                    }
                }
                #endif
            }
        }
    }

    // MARK: - Requests Section

    @ViewBuilder
    private var requestsSection: some View {
        Section {
            ChevronButton(
                L10n.SeerrSettings.title,
                content: seerrHostDescription,
                systemName: "popcorn"
            ) {
                router.route(to: .seerrSettings)
            }
        } header: {
            Text(L10n.SeerrSettings.requests)
        } footer: {
            Text(L10n.SeerrSettings.requestsFooter)
        }
    }

    private var seerrHostDescription: String {
        guard seerrService.isConfigured, let serverURL = seerrService.serverURL else {
            return L10n.SeerrSettings.notConnected
        }

        return serverURL.host() ?? serverURL.absoluteString
    }

    // MARK: - Customization Section

    @ViewBuilder
    private var customizeSection: some View {
        Section {
            #if os(iOS)
            Picker(L10n.appearance, selection: $appearance)
            #endif

            ColorPicker(L10n.accentColor, selection: $accentColor, supportsOpacity: false)

            ChevronButton(L10n.advanced) {
                router.route(to: .customizeSettingsView)
            }
        } header: {
            Text(L10n.customize)
        } footer: {
            Text(L10n.viewsMayRequireRestart)
        }
    }

    // MARK: - Diagnostics Section

    @ViewBuilder
    private var diagnosticsSection: some View {
        Section {

            if ExperimentalSettingsView.isEnabled {
                ChevronButton(L10n.experimental) {
                    router.route(to: .experimentalSettings)
                }
            }

            ChevronButton(L10n.logs) {
                router.route(to: .log)
            }

            #if DEBUG
            ChevronButton("Debug") {
                router.route(to: .debugSettings)
            }
            #endif
        }
    }
}
