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

    /// The only cell of the picker while no users are stored for the shown servers.
    struct EmptyUserView: View {

        let servers: OrderedSet<ServerState>

        private let columns: CGFloat = UIDevice.isPhone ? 2 : 5

        var body: some View {
            GeometryReader { geometry in
                AddPersonTile(servers: servers, reservesSubtitleSpace: false)
                    .frame(maxWidth: (geometry.size.width - EdgeInsets.edgePadding * (columns + 1)) / columns)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .focusSection()
            }
        }
    }

    // MARK: - Add person

    /// Opens sign-in for the shown server, or lets the person choose
    /// a server first when several servers are shown.
    ///
    /// Signing in returns to the picker with the new person on the couch
    /// (`Notifications[.didAddUser]`).
    struct AddPersonMenu<Label: View>: View {

        @Default(.selectUserServerSelection)
        private var serverSelection

        @Router
        private var router

        let servers: OrderedSet<ServerState>
        let label: () -> Label

        init(
            servers: OrderedSet<ServerState>,
            @ViewBuilder label: @escaping () -> Label
        ) {
            self.servers = servers
            self.label = label
        }

        /// The server to add a person to, or `nil` to choose one from a menu.
        private var server: ServerState? {
            if let selected = serverSelection.server(from: servers) {
                return selected
            }

            return servers.count == 1 ? servers.first : nil
        }

        private func addPerson(server: ServerState) {
            UIDevice.impact(.light)
            router.route(to: .userSignIn(server: server))
        }

        var body: some View {
            ConditionalMenu(tracking: server) { server in
                addPerson(server: server)
            } menuContent: {
                Text(L10n.selectServer)

                ForEach(servers) { server in
                    Button {
                        addPerson(server: server)
                    } label: {
                        Text(server.name)
                        Text(server.effectiveServerURL.absoluteString)
                    }
                }
            } label: {
                label()
            }
        }
    }

    /// An "Add person" cell in the look of a user avatar, for the grid.
    struct AddPersonTile: View {

        let servers: OrderedSet<ServerState>
        /// Reserves the height of a subtitle line, to line up with `CouchMemberButton`.
        var reservesSubtitleSpace: Bool = true

        @ViewBuilder
        private var imageView: some View {
            RelativeSystemImageView(systemName: "plus")
                .foregroundStyle(Color.secondary)
                .aspectRatio(1, contentMode: .fit)
                .backport
                .glassEffect(in: .circle)
        }

        @ViewBuilder
        private var titleView: some View {
            Text(L10n.CouchPicker.addPerson)
                .font(.headline)
                .fontWeight(.semibold)
                .lineLimit(1)

            if reservesSubtitleSpace {
                Text(L10n.CouchPicker.addPerson)
                    .font(.footnote)
                    .lineLimit(1)
                    .hidden()
                    .accessibilityHidden(true)
            }
        }

        var body: some View {
            AddPersonMenu(servers: servers) {
                // tvOS breaks HoverEffects when using a VStack
                #if os(tvOS)
                imageView
                    .hoverEffect(.highlight)

                titleView
                #else
                VStack {
                    imageView

                    titleView
                }
                #endif
            }
            .foregroundStyle(.primary, .secondary)
            .buttonBorderShape(.circle)
            #if os(tvOS)
            .buttonStyle(.borderless)
            #endif
        }
    }

    /// An "Add person" row in the look of a user row, for the list.
    struct AddPersonRow: View {

        let servers: OrderedSet<ServerState>

        var body: some View {
            AddPersonMenu(servers: servers) {
                HStack(spacing: EdgeInsets.edgePadding) {
                    RelativeSystemImageView(systemName: "plus")
                        .foregroundStyle(Color.secondary)
                        .aspectRatio(1, contentMode: .fit)
                        .backport
                        .glassEffect(in: .circle)
                        .frame(width: UIDevice.isTV ? 120 : UIDevice.isPad ? 80 : 50)

                    Text(L10n.CouchPicker.addPerson)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .foregroundStyle(.primary, .secondary)
        }
    }
}
