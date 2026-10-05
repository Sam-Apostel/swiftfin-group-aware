//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

extension SelectUserView {

    struct ListView: View {

        @Binding
        private var isEditing: Bool
        @Binding
        private var selectedUsers: Set<UserState>

        private let users: [UserItem]
        private let couchSelectionIDs: [String]
        private let kidUserIDs: Set<String>
        private let serverSelection: SelectUserServerSelection
        private let action: (UserState) -> Void
        private let onToggleKid: (UserState) -> Void
        private let onDelete: (UserState) -> Void

        /// - Parameters:
        ///   - couchSelectionIDs: The IDs of the users on the couch, in pick order.
        ///   - action: Toggles a user on or off the couch. Not called in edit mode.
        init(
            userItems: [UserItem],
            isEditing: Binding<Bool>,
            selectedUsers: Binding<Set<UserState>>,
            couchSelectionIDs: [String],
            kidUserIDs: Set<String>,
            serverSelection: SelectUserServerSelection,
            action: @escaping (UserState) -> Void,
            onToggleKid: @escaping (UserState) -> Void,
            onDelete: @escaping (UserState) -> Void
        ) {
            self.users = userItems
            self._isEditing = isEditing
            self._selectedUsers = selectedUsers
            self.couchSelectionIDs = couchSelectionIDs
            self.kidUserIDs = kidUserIDs
            self.serverSelection = serverSelection
            self.action = action
            self.onToggleKid = onToggleKid
            self.onDelete = onDelete
        }

        private func isOnCouch(_ user: UserState) -> Bool {
            couchSelectionIDs.contains(user.id)
        }

        private func isDimmed(_ user: UserState) -> Bool {
            !isEditing && couchSelectionIDs.isNotEmpty && !isOnCouch(user)
        }

        @ViewBuilder
        private func rowLabel(for item: UserItem) -> some View {
            HStack(spacing: EdgeInsets.edgePadding) {
                // `UserProfileImage` dims itself when editing and not selected
                UserProfileImage(
                    userID: item.user.id,
                    source: item.user.profileImageSource(
                        client: item.server.client
                    ),
                    pipeline: .Swiftfin.local
                )
                .isEditing(isEditing || isDimmed(item.user))
                .isSelected(isEditing && selectedUsers.contains(item.user))
                .subtleShadow()
                .frame(width: UIDevice.isTV ? 120 : UIDevice.isPad ? 80 : 50)

                VStack(alignment: .leading) {
                    HStack(spacing: UIDevice.isTV ? 16 : 6) {
                        Text(item.user.username)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .lineLimit(1)

                        if kidUserIDs.contains(item.user.id) {
                            Image(systemName: "figure.child")
                                .font(UIDevice.isTV ? .body : .footnote)
                                .fontWeight(.bold)
                                .foregroundStyle(Color.orange)
                                .accessibilityLabel(L10n.CouchPicker.kid)
                        }
                    }

                    if serverSelection == .all {
                        Text(item.server.name)
                            .font(UIDevice.isTV ? .body : .footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }

        @ViewBuilder
        private func row(for item: UserItem) -> some View {
            ChevronButton {
                if isEditing {
                    selectedUsers.toggle(value: item.user)
                } else {
                    action(item.user)
                }
            } label: {
                rowLabel(for: item)
            }
            .contextMenu {
                if !isEditing {
                    Button(
                        kidUserIDs.contains(item.user.id) ? L10n.CouchPicker.unmarkAsKid : L10n.CouchPicker.markAsKid,
                        systemImage: "figure.child"
                    ) {
                        onToggleKid(item.user)
                    }

                    Button(L10n.delete, role: .destructive) {
                        onDelete(item.user)
                    }
                }
            }
            // Outside of edit mode, the trailing checkbox shows the couch selection
            .isEditing(true)
            .isSelected(isEditing ? selectedUsers.contains(item.user) : isOnCouch(item.user))
            #if os(iOS)
            .swipeActions {
                if !isEditing {
                    Button(
                        L10n.delete,
                        systemImage: "trash"
                    ) {
                        onDelete(item.user)
                    }
                    .tint(.red)
                }
            }
            #endif
        }

        var body: some View {
            List {
                ForEach(users, id: \.user.id) { item in
                    row(for: item)
                }
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            #if os(iOS)
            .scrollContentBackground(.hidden)
            #else
            .edgePadding()
            .scrollClipDisabled()
            .focusSection()
            #endif
        }
    }
}
