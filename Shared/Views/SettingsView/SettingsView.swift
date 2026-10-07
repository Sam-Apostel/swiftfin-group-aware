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

/// Settings, grouped by what you're doing: who's on the couch, watching, how it looks,
/// and the connections behind it. Everything app-wide and diagnostic lives in About.
struct SettingsView: View {

    @Default(.Couch.lastMemberIDs)
    private var lastCouchMemberIDs
    @Default(.Couch.kidSafeBrowsing)
    private var kidSafeBrowsing
    @Default(.VideoPlayer.videoPlayerType)
    private var videoPlayerType

    @InjectedObject(\.userSessionManager)
    private var userSessionManager: UserSessionManager

    @Router
    private var router

    #if os(iOS)
    @InjectedObject(\.seerrService)
    private var seerrService: SeerrService
    #endif

    // MARK: - Body

    var body: some View {
        Form {
            couchSection
            watchingSection
            lookSection
            connectionsSection
            aboutSection
        } image: {
            FinView(variant: .tail)
                .frame(maxWidth: 560)
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
                Label(L10n.CouchSettings.changeWhosWatching, systemImage: "sofa.fill")
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
            .tint(Color.Couchfin.fin)
            #if os(iOS)
            .controlSize(.large)
            #endif
        }
    }

    @ViewBuilder
    private func couchMembersRow(couch: CouchGroup, server: ServerState) -> some View {
        #if os(tvOS)
        // A button, so the row is focusable with the Siri Remote
        Button {
            router.route(to: .couchSettings)
        } label: {
            couchMembersLabel(couch: couch, server: server)
        }
        #else
        couchMembersLabel(couch: couch, server: server)
        #endif
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

    // MARK: - Watching Section

    @ViewBuilder
    private var watchingSection: some View {
        Section(L10n.CouchfinSettings.watching) {
            ChevronButton(
                L10n.CouchfinSettings.playback,
                content: videoPlayerType.displayTitle,
                systemName: "play.fill"
            ) {
                router.route(to: .playbackSettings)
            }

            ChevronButton(
                L10n.CouchfinSettings.audioAndSubtitles,
                systemName: "captions.bubble.fill"
            ) {
                router.route(to: .audioSubtitleSettings)
            }

            if userSessionManager.currentSession != nil {
                ChevronButton(
                    L10n.CouchfinSettings.couchAndKids,
                    content: kidSafeBrowsing ? L10n.Couch.kidSafeBrowsing : "",
                    systemName: "figure.and.child.holdinghands"
                ) {
                    router.route(to: .couchSettings)
                }
            }
        }
    }

    // MARK: - Look Section

    @ViewBuilder
    private var lookSection: some View {
        Section {
            ChevronButton(
                L10n.CouchfinSettings.homeAndLibraries,
                systemName: "house.fill"
            ) {
                router.route(to: .customizeSettingsView)
            }

            ChevronButton(
                L10n.CouchfinSettings.postersAndItems,
                systemName: "rectangle.portrait.on.rectangle.portrait.fill"
            ) {
                router.route(to: .posterSettings)
            }
        } header: {
            Text(L10n.CouchfinSettings.look)
        } footer: {
            Text(L10n.viewsMayRequireRestart)
        }
    }

    // MARK: - Connections Section

    @ViewBuilder
    private var connectionsSection: some View {
        if let userSession = userSessionManager.currentSession {
            Section(L10n.CouchfinSettings.connections) {
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
                ChevronButton(
                    L10n.SeerrSettings.requests,
                    content: seerrHostDescription,
                    systemName: "popcorn.fill"
                ) {
                    router.route(to: .seerrSettings)
                }

                if userSession.user.data.policy?.isAdministrator == true {
                    ChevronButton(
                        L10n.CouchfinSettings.serverDashboard,
                        systemName: "server.rack"
                    ) {
                        router.route(to: .adminDashboard)
                    }
                }
                #endif
            }
        }
    }

    #if os(iOS)
    private var seerrHostDescription: String {
        guard seerrService.isConfigured, let serverURL = seerrService.serverURL else {
            return L10n.SeerrSettings.notConnected
        }

        return serverURL.host() ?? serverURL.absoluteString
    }
    #endif

    // MARK: - About Section

    @ViewBuilder
    private var aboutSection: some View {
        Section {
            ChevronButton(
                L10n.CouchfinSettings.about,
                content: UIApplication.appVersion ?? .emptyDash,
                systemName: "info.circle.fill"
            ) {
                router.route(to: .aboutApp)
            }
        }
    }
}
