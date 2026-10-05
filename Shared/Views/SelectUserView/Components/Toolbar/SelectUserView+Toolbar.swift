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

    struct Toolbar: View {

        private enum FocusedButton: Hashable {
            case center
            case start
        }

        @Default(.accentColor)
        private var accentColor

        @Environment(\.horizontalSizeClass)
        private var horizontalSizeClass

        @Binding
        private var isEditing: Bool
        @Binding
        private var selectedUsers: Set<UserState>

        @FocusState
        private var focusedButton: FocusedButton?

        private let servers: OrderedSet<ServerState>
        private let allUsers: [UserItem]
        private let couchMembers: [UserState]
        private let couchServer: ServerState?
        private let isStartingCouch: Bool
        private let onStart: () -> Void
        private let onDelete: () -> Void

        private func toggleUsers() {
            if selectedUsers.count == allUsers.count {
                selectedUsers.removeAll()
            } else {
                selectedUsers = Set(allUsers.map(\.user))
            }
        }

        private let buttonHeight: CGFloat = UIDevice.isTV ? 75 : 44
        private let startButtonHeight: CGFloat = UIDevice.isTV ? 75 : 50

        private var startButtonTitle: String {
            if couchMembers.count > 1 {
                L10n.CouchPicker.startWatchingTogether(couchMembers.count)
            } else {
                L10n.CouchPicker.startWatching
            }
        }

        private var defaultFocusedButton: FocusedButton {
            if !isEditing, couchMembers.isNotEmpty {
                .start
            } else {
                .center
            }
        }

        /// - Parameters:
        ///   - couchMembers: The users on the couch, in pick order.
        ///   - couchServer: The server of the users on the couch.
        ///   - onStart: Starts watching as the couch.
        init(
            servers: OrderedSet<ServerState>,
            allUsers: [UserItem],
            isEditing: Binding<Bool>,
            selectedUsers: Binding<Set<UserState>>,
            couchMembers: [UserState],
            couchServer: ServerState?,
            isStartingCouch: Bool,
            onStart: @escaping () -> Void,
            onDelete: @escaping () -> Void
        ) {
            self.servers = servers
            self.allUsers = allUsers
            self._isEditing = isEditing
            self._selectedUsers = selectedUsers
            self.couchMembers = couchMembers
            self.couchServer = couchServer
            self.isStartingCouch = isStartingCouch
            self.onStart = onStart
            self.onDelete = onDelete
        }

        var body: some View {
            if horizontalSizeClass == .compact {
                compactView
            } else {
                regularView
            }
        }

        @ViewBuilder
        private var compactView: some View {
            if !isEditing {
                VStack(spacing: 16) {
                    HStack(spacing: 16) {
                        ServerMenu(servers: servers)
                            .frame(height: buttonHeight)
                            .frame(maxWidth: 400)

                        AddUserMenu(servers: servers)
                            .frame(width: buttonHeight, height: buttonHeight)
                    }

                    if allUsers.isNotEmpty {
                        startButton
                            .frame(height: startButtonHeight)
                            .frame(maxWidth: 400 + 16 + buttonHeight)
                    }
                }
                .animation(.linear(duration: 0.1), value: couchMembers.map(\.id))
                .edgePadding([.bottom, .horizontal])
            }
        }

        @ViewBuilder
        private var regularView: some View {
            HStack(alignment: .top, spacing: UIDevice.isTV ? 32 : nil) {
                if isEditing {
                    editView
                } else {
                    regularContentView
                }
            }
            .animation(.linear(duration: 0.1), value: selectedUsers.isNotEmpty)
            .animation(.linear(duration: 0.1), value: couchMembers.map(\.id))
            .frame(height: buttonHeight)
            .frame(maxWidth: .infinity)
            .focusSection()
            .edgePadding([.bottom, .horizontal])
            .defaultFocus(
                $focusedButton,
                defaultFocusedButton,
                priority: .userInitiated
            )
        }

        @ViewBuilder
        private var startButton: some View {
            Button(action: onStart) {
                HStack(spacing: UIDevice.isTV ? 24 : 12) {
                    if let couchServer, couchMembers.isNotEmpty {
                        CouchAvatarStack(
                            users: couchMembers,
                            server: couchServer,
                            size: UIDevice.isTV ? 50 : 30
                        )
                    }

                    Text(startButtonTitle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    if isStartingCouch {
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .fontWeight(.semibold)
            .backport
            .buttonStyle(.glassProminent.shadow(false))
            .tint(accentColor)
            #if os(iOS)
            .controlSize(.large)
            #endif
            // Not disabled while starting: on tvOS a disabled button loses focus,
            // and `onStart` already ignores taps while a start is in progress.
            .disabled(couchMembers.isEmpty)
            .focused($focusedButton, equals: .start)
        }

        @ViewBuilder
        private var editView: some View {
            Button(action: toggleUsers) {
                Text(selectedUsers.count == allUsers.count ? L10n.removeAll : L10n.selectAll)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minWidth: 100, maxWidth: 300)

            Button {
                isEditing = false
            } label: {
                Text(L10n.cancel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minWidth: 100, maxWidth: 300)
            .focused($focusedButton, equals: .center)

            Button(role: .destructive, action: onDelete) {
                Text(L10n.delete)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minWidth: 100, maxWidth: 300)
            .disabled(selectedUsers.isEmpty)
        }

        @ViewBuilder
        private var regularContentView: some View {
            Menu {
                AdvancedMenuContent(
                    hasUsers: allUsers.isNotEmpty,
                    isEditing: $isEditing
                )
            } label: {
                Label(L10n.advanced, systemImage: "gearshape.fill")
                    .labelStyle(.iconOnly)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .foregroundStyle(.primary, .secondary)
            .menuOrder(.fixed)
            .symbolRenderingMode(.monochrome)
            .frame(width: buttonHeight, height: buttonHeight)
            .buttonBorderShape(.circle)
            .backport
            .glassEffect(in: .circle)

            ServerMenu(servers: servers)
                .frame(maxWidth: UIDevice.isTV ? 600 : 400)
                .frame(height: buttonHeight)
                .focused($focusedButton, equals: .center)

            if allUsers.isNotEmpty {
                startButton
                    .frame(maxWidth: UIDevice.isTV ? 700 : 400)
                    .frame(height: buttonHeight)
            }

            AddUserMenu(servers: servers)
                .frame(width: buttonHeight, height: buttonHeight)
                .hidden(allUsers.isEmpty)
        }
    }
}
