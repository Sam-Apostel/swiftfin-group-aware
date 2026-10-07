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

struct CouchSettingsView: View {

    @Default(.Couch.kidSafeBrowsing)
    private var kidSafeBrowsing
    @Default(.Couch.hideWatchedByAnyMember)
    private var hideWatchedByAnyMember

    #if os(tvOS)
    @Default(.appleTVDefaultPersonID)
    private var appleTVDefaultPersonID
    #endif

    @InjectedObject(\.userSessionManager)
    private var userSessionManager: UserSessionManager

    /// Stored users on the current server, sorted by name.
    @State
    private var users: [UserState] = []

    /// IDs of the users in `users` that are flagged as kids.
    ///
    /// Mirrors `UserState.isKid`, which is not observable.
    @State
    private var kidIDs: Set<String> = []

    // MARK: - Body

    var body: some View {
        Form(systemImage: "sofa.fill") {
            #if os(tvOS)
            if AppleTVProfile.isAvailable {
                appleTVProfileSection
            }
            #endif

            browsingSection

            kidsSection
        }
        .navigationTitle(L10n.CouchSettings.couchSettings)
        .onAppear {
            loadUsers()
        }
    }

    // MARK: - Apple TV Profile Section

    #if os(tvOS)
    @ViewBuilder
    private var appleTVProfileSection: some View {
        Section {
            ListRowMenu(
                L10n.CouchfinSettings.opensAs,
                subtitle: users.first(where: { $0.id == appleTVDefaultPersonID })?.username ?? L10n.CouchfinSettings.askEveryTime
            ) {
                Picker(L10n.CouchfinSettings.opensAs, selection: $appleTVDefaultPersonID) {
                    Text(L10n.CouchfinSettings.askEveryTime)
                        .tag(String?.none)

                    ForEach(users, id: \.id) { user in
                        Text(user.username)
                            .tag(String?.some(user.id))
                    }
                }
            }
        } header: {
            Text(L10n.CouchfinSettings.appleTVProfile)
        } footer: {
            Text(L10n.CouchfinSettings.opensAsFooter)
        }
    }
    #endif

    // MARK: - Browsing Section

    @ViewBuilder
    private var browsingSection: some View {
        Section {
            Toggle(L10n.Couch.kidSafeBrowsing, isOn: $kidSafeBrowsing)
        } footer: {
            Text(L10n.CouchSettings.kidSafeBrowsingFooter)
        }

        Section {
            Toggle(L10n.CouchSettings.hideWatchedByAnyMember, isOn: $hideWatchedByAnyMember)
        } footer: {
            Text(L10n.CouchSettings.hideWatchedByAnyMemberFooter)
        }
    }

    // MARK: - Kids Section

    @ViewBuilder
    private var kidsSection: some View {
        Section {
            if users.isEmpty {
                Text(L10n.CouchSettings.noUsers)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(users, id: \.id) { user in
                    Toggle(isOn: kidBinding(for: user)) {
                        kidRowLabel(user: user)
                    }
                }
            }
        } header: {
            Text(L10n.CouchSettings.kids)
        } footer: {
            Text(L10n.CouchSettings.kidsFooter)
        }
    }

    @ViewBuilder
    private func kidRowLabel(user: UserState) -> some View {
        HStack(spacing: UIDevice.isTV ? 20 : 12) {
            if let server = userSessionManager.currentSession?.server {
                UserProfileImage(
                    userID: user.id,
                    source: user.profileImageSource(
                        client: server.client
                    ),
                    pipeline: .Swiftfin.local
                )
                .frame(width: UIDevice.isTV ? 60 : 36, height: UIDevice.isTV ? 60 : 36)
            }

            Text(user.username)
                .lineLimit(1)
        }
    }

    // MARK: - Helpers

    private func kidBinding(for user: UserState) -> Binding<Bool> {
        Binding(
            get: {
                kidIDs.contains(user.id)
            },
            set: { newValue in
                user.isKid = newValue

                if newValue {
                    kidIDs.insert(user.id)
                } else {
                    kidIDs.remove(user.id)
                }
            }
        )
    }

    private func loadUsers() {
        guard let serverID = userSessionManager.currentSession?.server.id else {
            users = []
            kidIDs = []
            return
        }

        let serverUsers = StoredValues[.User.users]
            .filter { $0.serverID == serverID }
            .sorted { $0.username.localizedStandardCompare($1.username) == .orderedAscending }

        users = serverUsers
        kidIDs = Set(serverUsers.filter(\.isKid).map(\.id))
    }
}
