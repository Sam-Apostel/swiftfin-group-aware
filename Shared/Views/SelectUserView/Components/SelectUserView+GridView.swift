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

// TODO: remember last focused user for tvOS focus

extension SelectUserView {

    struct GridView: PlatformView {

        /// A grid cell: a user, or the trailing "Add person" tile.
        private enum Cell {
            case user(UserItem)
            case addPerson

            var id: String {
                switch self {
                case let .user(item):
                    item.user.id
                case .addPerson:
                    "addPerson"
                }
            }
        }

        @Binding
        private var isEditing: Bool
        @Binding
        private var selectedUsers: Set<UserState>

        private let couchSelectionIDs: [String]
        private let kidUserIDs: Set<String>
        private let needsSignInUserIDs: Set<String>
        private let kidWithoutLimitUserIDs: Set<String>
        private let focusedUserID: FocusState<String?>.Binding?
        private let onWatchAlone: (UserState) -> Void
        private let onDelete: (UserState) -> Void
        private let onToggleKid: (UserState) -> Void
        private let onSignInAgain: (UserItem) -> Void
        private let action: (UserState) -> Void
        private let serverSelection: SelectUserServerSelection
        private let servers: OrderedSet<ServerState>
        private let userItems: [UserItem]

        /// - Parameters:
        ///   - couchSelectionIDs: The IDs of the users on the couch, in pick order.
        ///   - needsSignInUserIDs: The IDs of the users without a stored access token.
        ///   - servers: The servers a person can be added to with the "Add person" tile.
        ///   - action: Toggles a user on or off the couch. Not called in edit mode.
        ///   - onSignInAgain: Opens sign-in with the user's name filled in.
        ///   - kidWithoutLimitUserIDs: The IDs of the kids whose server account has no age limit.
        ///   - focusedUserID: The picker's focus on tvOS, to give the first person initial focus.
        ///   - onWatchAlone: "Watch as just <name>": starts a couch of only this user.
        init(
            userItems: [UserItem],
            isEditing: Binding<Bool>,
            selectedUsers: Binding<Set<UserState>>,
            couchSelectionIDs: [String],
            kidUserIDs: Set<String>,
            needsSignInUserIDs: Set<String>,
            serverSelection: SelectUserServerSelection,
            servers: OrderedSet<ServerState>,
            action: @escaping (UserState) -> Void,
            onToggleKid: @escaping (UserState) -> Void,
            onSignInAgain: @escaping (UserItem) -> Void,
            onDelete: @escaping (UserState) -> Void,
            kidWithoutLimitUserIDs: Set<String> = [],
            focusedUserID: FocusState<String?>.Binding? = nil,
            onWatchAlone: @escaping (UserState) -> Void = { _ in }
        ) {
            self.userItems = userItems
            self._isEditing = isEditing
            self._selectedUsers = selectedUsers
            self.couchSelectionIDs = couchSelectionIDs
            self.kidUserIDs = kidUserIDs
            self.needsSignInUserIDs = needsSignInUserIDs
            self.serverSelection = serverSelection
            self.servers = servers
            self.action = action
            self.onToggleKid = onToggleKid
            self.onSignInAgain = onSignInAgain
            self.onDelete = onDelete
            self.kidWithoutLimitUserIDs = kidWithoutLimitUserIDs
            self.focusedUserID = focusedUserID
            self.onWatchAlone = onWatchAlone
        }

        /// The users, then "Add person" outside of edit mode.
        private var cells: [Cell] {
            let users = userItems.map { Cell.user($0) }

            return isEditing ? users : users + [.addPerson]
        }

        @ViewBuilder
        private func userGridButton(for item: UserItem) -> some View {
            if isEditing {
                UserButton(
                    user: item.user,
                    server: item.server,
                    showServer: serverSelection == .all
                ) {
                    selectedUsers.toggle(value: item.user)
                } onDelete: {
                    onDelete(item.user)
                }
                .isSelected(selectedUsers.contains(item.user))
            } else {
                CouchMemberButton(
                    user: item.user,
                    server: item.server,
                    showServer: serverSelection == .all,
                    isSelected: couchSelectionIDs.contains(item.user.id),
                    isDimmed: couchSelectionIDs.isNotEmpty && !couchSelectionIDs.contains(item.user.id),
                    isKid: kidUserIDs.contains(item.user.id),
                    action: {
                        action(item.user)
                    },
                    onToggleKid: {
                        onToggleKid(item.user)
                    },
                    onDelete: {
                        onDelete(item.user)
                    },
                    needsSignIn: needsSignInUserIDs.contains(item.user.id),
                    onSignInAgain: {
                        onSignInAgain(item)
                    },
                    isKidWithoutServerLimit: kidWithoutLimitUserIDs.contains(item.user.id),
                    onWatchAlone: {
                        onWatchAlone(item.user)
                    }
                )
                .couchPickerFocused(focusedUserID, userID: item.user.id)
            }
        }

        @ViewBuilder
        private func cellView(for cell: Cell) -> some View {
            switch cell {
            case let .user(item):
                userGridButton(for: item)
            case .addPerson:
                AddPersonTile(servers: servers)
            }
        }

        var iOSView: some View {
            CenteredLazyVGrid(
                data: cells,
                id: \.id,
                columns: UIDevice.isPhone ? 2 : 5,
                spacing: EdgeInsets.itemSpacing
            ) { cell in
                cellView(for: cell)
            }
            .edgePadding(UIDevice.isPhone ? [.horizontal, .vertical] : .horizontal)
            .scrollIfLargerThanContainer(axes: .vertical, padding: 100)
        }

        var tvOSView: some View {
            HStack(spacing: EdgeInsets.itemSpacing) {
                ForEach(cells, id: \.id) { cell in
                    cellView(for: cell)
                        .frame(width: 300)
                }
            }
            .edgePadding(.horizontal)
            .focusSection()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scrollIfLargerThanContainer(axes: .horizontal)
            #if os(tvOS)
            .scrollClipDisabled()
            #endif
        }
    }
}
