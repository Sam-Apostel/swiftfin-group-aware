//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import OrderedCollections
import SwiftUI

extension SelectUserView {

    struct AdvancedMenuContent: View {

        @Default(.selectUserDisplayType)
        private var userListDisplayType
        @Default(.selectUserSortOrder)
        private var userSortOrder

        @Router
        private var router

        let hasUsers: Bool
        let isEditing: Binding<Bool>
        /// With exactly one server the server menu is hidden, and "Add server"
        /// and "Edit server" are shown here instead.
        var servers: OrderedSet<ServerState> = []

        var body: some View {
            if hasUsers {
                Toggle(
                    L10n.editUsers,
                    systemImage: "person.crop.circle",
                    isOn: isEditing
                )
            }

            Picker(selection: $userListDisplayType) {
                ForEach(LibraryDisplayType.allCases, id: \.hashValue) {
                    Label($0.displayTitle, systemImage: $0.systemImage)
                        .tag($0)
                }
            } label: {
                Text(L10n.layout)
                Text(userListDisplayType.displayTitle)
                Image(systemName: userListDisplayType.systemImage)
            }
            .pickerStyle(.menu)

            Picker(selection: $userSortOrder) {
                ForEach(SelectUserSortOrder.allCases, id: \.hashValue) {
                    Label($0.displayTitle, systemImage: $0.systemImage)
                        .tag($0)
                }
            } label: {
                Text(L10n.sort)
                Text(userSortOrder.displayTitle)
                Image(systemName: userSortOrder.systemImage)
            }
            .pickerStyle(.menu)

            if servers.count == 1 {
                Section {
                    ServerActionButtons(server: servers.first)
                }
            }

            Section {
                Button(L10n.advanced, systemImage: "gearshape.fill") {
                    router.route(to: .appSettings)
                }
            }
        }
    }
}
