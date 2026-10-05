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
import OrderedCollections
import SwiftUI

struct SelectUserView: View {

    typealias UserItem = (user: UserState, server: ServerState)

    @Default(.accentColor)
    private var accentColor
    @Default(.selectUserUseSplashscreen)
    private var selectUserUseSplashscreen
    @Default(.selectUserAllServersSplashscreen)
    private var selectUserAllServersSplashscreen
    @Default(.selectUserServerSelection)
    private var serverSelection
    @Default(.selectUserDisplayType)
    private var userListDisplayType
    @Default(.selectUserSortOrder)
    private var userSortOrder

    @Environment(\.localUserAuthenticationAction)
    private var authenticationAction
    @Environment(\.horizontalSizeClass)
    private var horizontalSizeClass

    @Injected(\.userSessionManager)
    private var userSessionManager: UserSessionManager

    @InjectedObject(\.couchPresetStore)
    private var couchPresetStore

    @Router
    private var router

    /// The users on the couch, in pick order. The first pick is the preferred primary user.
    @State
    private var couchSelection: [UserState] = []
    @State
    private var hasRestoredLastCouch = false
    @State
    private var isStartingCouch = false
    @State
    private var kidUserIDs: Set<String> = []
    /// The users selected for deletion in edit mode, separate from the couch selection.
    @State
    private var selectedUsers: Set<UserState> = []
    @State
    private var isEditing = false
    @State
    private var isPresentingConfirmDeleteUsers = false
    /// The couch preset being saved or edited in the name + emoji prompt.
    @State
    private var presetDraft: CouchPresetDraft?

    @StateObject
    private var viewModel = SelectUserViewModel()

    private var selectedServer: ServerState? {
        serverSelection.server(from: viewModel.servers.keys)
    }

    private var areAllUsersSelected: Bool {
        selectedUsers.count == userItems.count
    }

    private func toggleAllUsersSelected() {
        if areAllUsersSelected {
            selectedUsers.removeAll()
        } else {
            selectedUsers.insert(contentsOf: userItems.map(\.user))
        }
    }

    private var splashScreenImageSources: [ImageSource] {
        switch (serverSelection, selectUserAllServersSplashscreen) {
        case (.all, .all):
            viewModel
                .servers
                .keys
                .shuffled()
                .map(\.splashScreenImageSource)

        case let (.server(id), _), let (.all, .server(id)):
            viewModel
                .servers
                .keys
                .first(where: { $0.id == id })
                .map { [$0.splashScreenImageSource] } ?? []
        }
    }

    private var userItems: [UserItem] {
        let items: [UserItem] = {
            switch serverSelection {
            case .all:
                return viewModel.servers
                    .map { server, users in
                        users.map { UserItem(user: $0, server: server) }
                    }
                    .flattened()

            case let .server(id: id):
                guard let server = viewModel.servers.keys.first(where: { $0.id == id }) else {
                    return []
                }

                return viewModel.servers[server]!
                    .map { UserItem(user: $0, server: server) }
            }
        }()

        return {
            switch userSortOrder {
            case .name:
                items.sorted(using: \.user.username)
            case .lastSeen:
                items.sorted { lhs, rhs in
                    let lhsDate = lhs.user.data.lastActivityDate ?? .distantPast
                    let rhsDate = rhs.user.data.lastActivityDate ?? .distantPast
                    return lhsDate < rhsDate
                }
            }
        }()
    }

    private var storedUsers: [UserState] {
        viewModel.servers.values.flattened()
    }

    /// The server of the users on the couch. Couch members always share a server.
    private var couchServer: ServerState? {
        guard let serverID = couchSelection.first?.serverID else { return nil }

        return viewModel.servers.keys.first { $0.id == serverID }
    }

    private func addUser(server: ServerState) {
        UIDevice.impact(.light)
        router.route(to: .userSignIn(server: server))
    }

    private func delete(user: UserState) {
        selectedUsers.insert(user)
        isPresentingConfirmDeleteUsers = true
    }

    // MARK: - Couch

    private func toggleCouch(user: UserState) {
        UIDevice.impact(.light)

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if couchSelection.contains(where: { $0.id == user.id }) {
                couchSelection.removeAll { $0.id == user.id }
            } else if let first = couchSelection.first, first.serverID != user.serverID {
                // Couch members must share a server: start a new couch with this user
                couchSelection = [user]
            } else {
                couchSelection.append(user)
            }
        }
    }

    private func toggleKid(user: UserState) {
        let isKid = !user.isKid
        user.isKid = isKid

        if isKid {
            kidUserIDs.insert(user.id)
        } else {
            kidUserIDs.remove(user.id)
        }

        UIDevice.impact(.light)
    }

    /// Keeps the couch selection in sync with the stored users and
    /// pre-selects the last couch once the users are first loaded.
    private func syncCouchSelection() {
        let users = storedUsers
        kidUserIDs = Set(users.filter(\.isKid).map(\.id))

        if !hasRestoredLastCouch, users.isNotEmpty {
            hasRestoredLastCouch = true
            couchSelection = lastCouch(from: users)
        } else {
            // Drop deleted users and pick up renamed users
            couchSelection = couchSelection.compactMap { member in
                users.first { $0.id == member.id }
            }
        }
    }

    private func lastCouch(from users: [UserState]) -> [UserState] {
        let members = Defaults[.Couch.lastMemberIDs].compactMap { id in
            users.first { $0.id == id }
        }

        guard let serverID = members.first?.serverID else { return [] }

        // Only pre-select users that are shown with the current server selection
        if case let .server(id) = serverSelection, id != serverID {
            return []
        }

        return members.filter { $0.serverID == serverID }
    }

    /// Runs each member's local access policy one after another, since only
    /// one PIN prompt can be presented at a time, then signs in as the couch.
    private func startCouch() {
        let members = couchSelection

        guard members.isNotEmpty, !isStartingCouch else { return }

        isStartingCouch = true

        Task { @MainActor in
            defer {
                isStartingCouch = false
            }

            do {
                guard let authenticationAction else { return }

                var isAfterPrompt = false

                for member in members {
                    let policy = member.accessPolicy

                    if policy != .none, isAfterPrompt {
                        // Let the previous prompt dismiss before presenting the next one
                        try await Task.sleep(for: .milliseconds(600))
                    }

                    let evaluatedPolicy = try await authenticationAction(
                        policy: policy,
                        reason: policy.authenticateReason(user: member)
                    )
                    let pin = (evaluatedPolicy as? PinEvaluatedUserAccessPolicy)?.pin ?? ""

                    try viewModel.validatePin(pin, for: member)

                    isAfterPrompt = policy != .none
                }

                try await userSessionManager.signIn(userIDs: members.map(\.id))
                couchPresetStore.recordRecent(memberIDs: members.map(\.id))
                UIDevice.feedback(.success)
            } catch is CancellationError {
                return
            } catch {
                await viewModel.error(error)
            }
        }
    }

    // MARK: - Couch presets

    /// Saved couches and the last couches of the shown users.
    private var couchChips: [CouchChip] {
        let items = userItems
        let shownServerIDs = Set(items.map(\.server.id))
        let presets = viewModel.servers
            .keys
            .filter { shownServerIDs.contains($0.id) }
            .flatMap { couchPresetStore.presets(serverID: $0.id) }

        return CouchPresetSync.chips(
            presets: presets,
            recents: couchPresetStore.recentCouches,
            usernames: Dictionary(items.map { ($0.user.id, $0.user.username) }) { first, _ in first },
            serverIDs: Dictionary(items.map { ($0.user.id, $0.server.id) }) { first, _ in first }
        )
    }

    /// The saved couch with exactly the people on the couch, if any.
    private var couchSelectionPreset: CouchPreset? {
        guard let couchServer, couchSelection.isNotEmpty else { return nil }

        return couchPresetStore.preset(
            serverID: couchServer.id,
            memberIDs: Set(couchSelection.map(\.id))
        )
    }

    private func chipServer(_ chip: CouchChip) -> ServerState? {
        guard let firstID = chip.memberIDs.first,
              let serverID = storedUsers.first(where: { $0.id == firstID })?.serverID
        else { return nil }

        return viewModel.servers.keys.first { $0.id == serverID }
    }

    private func refreshCouchPresets() {
        couchPresetStore.seedRecentsIfNeeded()

        for (server, users) in viewModel.servers where users.isNotEmpty {
            couchPresetStore.refresh(server: server, users: users)
        }
    }

    /// Puts the chip's people on the couch, or starts watching when they already are.
    private func selectChip(_ chip: CouchChip) {
        let members = chip.memberIDs.compactMap { id in
            storedUsers.first { $0.id == id }
        }

        guard members.isNotEmpty else { return }

        if Set(couchSelection.map(\.id)) == chip.memberSet {
            startCouch()
            return
        }

        UIDevice.impact(.light)

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            couchSelection = members
        }
    }

    /// "Save this couch…" from the start bar, or edits the saved couch with the same people.
    private func saveCurrentCouch() {
        guard let couchServer, couchSelection.isNotEmpty else { return }

        if let preset = couchSelectionPreset {
            editPreset(preset, server: couchServer)
            return
        }

        presetDraft = CouchPresetDraft(
            presetID: nil,
            serverID: couchServer.id,
            memberIDs: couchSelection.map(\.id),
            memberNames: couchSelection.map(\.username),
            name: "",
            emoji: couchSelection.contains(where: \.isKid) ? "🧸" : "🛋️"
        )
    }

    private func saveChip(_ chip: CouchChip) {
        guard let server = chipServer(chip) else { return }

        presetDraft = CouchPresetDraft(
            presetID: nil,
            serverID: server.id,
            memberIDs: chip.memberIDs,
            memberNames: chip.memberNames,
            name: "",
            emoji: kidUserIDs.isDisjoint(with: chip.memberSet) ? "🛋️" : "🧸"
        )
    }

    private func editChip(_ chip: CouchChip) {
        guard let preset = chip.preset, let server = chipServer(chip) else { return }

        editPreset(preset, server: server)
    }

    private func editPreset(_ preset: CouchPreset, server: ServerState) {
        let names = preset.memberIDs.compactMap { id in
            storedUsers.first { $0.id == id }?.username
        }

        presetDraft = CouchPresetDraft(
            presetID: preset.id,
            serverID: server.id,
            memberIDs: preset.memberIDs,
            memberNames: names,
            name: preset.name,
            emoji: preset.emoji ?? ""
        )
    }

    private func deleteChip(_ chip: CouchChip) {
        guard let preset = chip.preset, let server = chipServer(chip) else { return }

        withAnimation(.linear(duration: 0.1)) {
            couchPresetStore.delete(
                presetID: preset.id,
                server: server,
                users: viewModel.servers[server] ?? []
            )
        }
        UIDevice.impact(.light)
    }

    private func forgetChip(_ chip: CouchChip) {
        withAnimation(.linear(duration: 0.1)) {
            couchPresetStore.forgetRecent(memberIDs: chip.memberIDs)
        }
        UIDevice.impact(.light)
    }

    private func commitPresetDraft(_ draft: CouchPresetDraft) {
        let name = CouchPreset.sanitizedName(draft.name)

        guard name.isNotEmpty,
              let server = viewModel.servers.keys.first(where: { $0.id == draft.serverID })
        else { return }

        let existing = draft.presetID.flatMap { id in
            couchPresetStore.presets(serverID: server.id).first { $0.id == id }
        }

        var preset = existing ?? CouchPreset(name: name, memberIDs: draft.memberIDs)
        preset.name = name
        preset.emoji = CouchPreset.sanitizedEmoji(draft.emoji)

        withAnimation(.linear(duration: 0.1)) {
            couchPresetStore.save(
                preset,
                server: server,
                users: viewModel.servers[server] ?? []
            )
        }
        UIDevice.feedback(.success)
    }

    @ViewBuilder
    private var couchChipsView: some View {
        let chips = couchChips

        if !isEditing, CouchPresetSync.shouldShowChips(chips) {
            CouchPresetChips(
                chips: chips,
                selectedMemberIDs: Set(couchSelection.map(\.id)),
                userItems: userItems,
                onSelect: { selectChip($0) },
                onEdit: { editChip($0) },
                onDelete: { deleteChip($0) },
                onSave: { saveChip($0) },
                onForget: { forgetChip($0) }
            )
            .padding(.bottom, UIDevice.isTV ? 10 : 8)
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var splashScreenBackground: some View {
        if selectUserUseSplashscreen, splashScreenImageSources.isNotEmpty {
            AlternateLayoutView {
                Color.clear
            } content: {
                ImageView(splashScreenImageSources)
                    .pipeline(.Swiftfin.local)
                    .aspectRatio(contentMode: .fill)
                    .id(splashScreenImageSources)
            }
            .overlay {
                Color.black
                    .opacity(0.9)
            }
        }
    }

    @ViewBuilder
    private var headerView: some View {
        if !isEditing, userItems.isNotEmpty {
            VStack(spacing: UIDevice.isTV ? 8 : 4) {
                Text(L10n.CouchPicker.title)
                    .font(UIDevice.isTV ? .title3 : .title2)
                    .fontWeight(.bold)

                Text(L10n.CouchPicker.subtitle)
                    .font(UIDevice.isTV ? .callout : .subheadline)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .edgePadding(.horizontal)
            .padding(.top, UIDevice.isTV ? 0 : 8)
            .padding(.bottom, UIDevice.isTV ? 20 : 8)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var contentView: some View {
        VStack(spacing: 0) {
            headerView

            couchChipsView

            ZStack {
                if userItems.isEmpty {
                    EmptyUserView {
                        if let selectedServer {
                            addUser(server: selectedServer)
                        }
                    }
                    .contextMenu {
                        if selectedServer == nil {
                            Text(L10n.selectServer)

                            ForEach(viewModel.servers.keys) { server in
                                Button {
                                    addUser(server: server)
                                } label: {
                                    Text(server.name)
                                    Text(server.effectiveServerURL.absoluteString)
                                }
                            }
                        }
                    }
                } else {
                    switch userListDisplayType {
                    case .list:
                        ListView(
                            userItems: userItems,
                            isEditing: $isEditing,
                            selectedUsers: $selectedUsers,
                            couchSelectionIDs: couchSelection.map(\.id),
                            kidUserIDs: kidUserIDs,
                            serverSelection: serverSelection,
                            action: { toggleCouch(user: $0) },
                            onToggleKid: { toggleKid(user: $0) },
                            onDelete: { delete(user: $0) }
                        )

                    case .grid:
                        GridView(
                            userItems: userItems,
                            isEditing: $isEditing,
                            selectedUsers: $selectedUsers,
                            couchSelectionIDs: couchSelection.map(\.id),
                            kidUserIDs: kidUserIDs,
                            serverSelection: serverSelection,
                            action: { toggleCouch(user: $0) },
                            onToggleKid: { toggleKid(user: $0) },
                            onDelete: { delete(user: $0) }
                        )
                    }
                }
            }
            .animation(.linear(duration: 0.1), value: userListDisplayType)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .focusSection()
            .mask {
                VStack(spacing: 0) {
                    #if os(tvOS)
                    if userListDisplayType == .list {
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .white, location: 1),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 30)
                    }
                    #endif

                    Color.white

                    LinearGradient(
                        stops: [
                            .init(color: .white, location: 0),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 30)
                }
                .ignoresSafeArea(.all, edges: .horizontal)
            }

            Toolbar(
                servers: viewModel.servers.keys,
                allUsers: userItems,
                isEditing: $isEditing,
                selectedUsers: $selectedUsers,
                couchMembers: couchSelection,
                couchServer: couchServer,
                isStartingCouch: isStartingCouch,
                onStart: startCouch,
                onDelete: {
                    isPresentingConfirmDeleteUsers = true
                },
                isCouchSaved: couchSelectionPreset != nil,
                onSaveCouch: saveCurrentCouch
            )
            .focusSection()
        }
        .animation(.linear(duration: 0.1), value: isEditing)
    }

    var body: some View {
        ZStack {
            switch viewModel.state {
            case .initial, .loading:
                ProgressView()
            case .content:
                if viewModel.servers.isEmpty {
                    ConnectToJellyfinView()
                } else {
                    contentView
                }
            }
        }
        .animation(.linear(duration: 0.1), value: viewModel.state)
        .animation(.linear(duration: 0.1), value: selectedServer)
        .withViewContext(.isOverComplexContent)
        .isEditing(isEditing)
        .onFirstAppear {
            viewModel.getServers()
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Image(.jellyfinBlobBlue)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: UIDevice.isTV ? 100 : 30)
            }

            #if os(iOS)
            if horizontalSizeClass == .compact {
                ToolbarItem(placement: .topBarLeading) {
                    if isEditing {
                        Button(
                            areAllUsersSelected ? L10n.removeAll : L10n.selectAll,
                            action: toggleAllUsersSelected
                        )
                        .foregroundStyle(.primary, .secondary)
                        .if(true) { view in
                            if #available(iOS 26.0, *) {
                                view
                            } else {
                                view
                                    .backport
                                    .buttonStyle(.glass)
                            }
                        }
                        .controlSize(.small)
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    if isEditing {
                        Button(L10n.cancel, role: .cancel) {
                            isEditing = false
                        }
                        .foregroundStyle(.primary, .secondary)
                        .if(true) { view in
                            if #available(iOS 26.0, *) {
                                view
                            } else {
                                view
                                    .backport
                                    .buttonStyle(.glass)
                            }
                        }
                        .controlSize(.small)
                    } else {
                        Menu(
                            L10n.advanced,
                            systemImage: "gearshape.fill"
                        ) {
                            AdvancedMenuContent(
                                hasUsers: userItems.isNotEmpty,
                                isEditing: $isEditing
                            )
                        }
                        .backport
                        .buttonStyle(.glass)
                        .controlSize(.small)
                    }
                }

                ToolbarItem(placement: .bottomBar) {
                    if isEditing {
                        Button(L10n.delete, role: .destructive) {
                            isPresentingConfirmDeleteUsers = true
                        }
                        .backport
                        .buttonStyle(.glassProminent)
                        .disabled(selectedUsers.isEmpty)
                    }
                }
            }
            #endif
        }
        .background {
            splashScreenBackground
                .ignoresSafeArea()
        }
        #if os(iOS)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        #endif
        .onChange(of: isEditing) {
            guard !isEditing, !isPresentingConfirmDeleteUsers else { return }

            selectedUsers.removeAll()
        }
        .onChange(of: isPresentingConfirmDeleteUsers) {
            // A delete from a context menu outside of edit mode was cancelled
            guard !isPresentingConfirmDeleteUsers, !isEditing else { return }

            selectedUsers.removeAll()
        }
        .onChange(of: storedUsers, initial: true) {
            syncCouchSelection()
            refreshCouchPresets()
        }
        .onChange(of: serverSelection) {
            // Keep the couch visible: clear it when switching to another server
            if case let .server(id) = serverSelection, let first = couchSelection.first, first.serverID != id {
                couchSelection.removeAll()
            }
        }
        .onChange(of: viewModel.servers.keys) {
            let newValue = viewModel.servers.keys
            if case let SelectUserServerSelection.server(id: id) = serverSelection,
               !newValue.contains(where: { $0.id == id })
            {
                if newValue.count == 1, let firstServer = newValue.first {
                    let newSelection = SelectUserServerSelection.server(id: firstServer.id)
                    serverSelection = newSelection
                    selectUserAllServersSplashscreen = newSelection
                } else {
                    serverSelection = .all
                    selectUserAllServersSplashscreen = .all
                }
            }
        }
        .onReceive(viewModel.$error) { error in
            guard error != nil else { return }

            UIDevice.feedback(.error)
        }
        .onReceive(viewModel.events) { event in
            switch event {
            case let .signedIn(user):
                Task { @MainActor in
                    do {
                        try await userSessionManager.signIn(userID: user.id)
                        UIDevice.feedback(.success)
                    } catch {
                        await viewModel.error(error)
                    }
                }
            }
        }
        .onNotification(.didConnectToServer) { server in
            viewModel.background.getServers()
            serverSelection = .server(id: server.id)
        }
        .onNotification(.didChangeServerConnection) { _ in
            viewModel.background.getServers()
        }
        .onNotification(.didDeleteServer) { _ in
            viewModel.background.getServers()
        }
        .alert(
            L10n.delete,
            isPresented: $isPresentingConfirmDeleteUsers
        ) {
            Button(L10n.delete, role: .destructive) {
                viewModel.deleteUsers(selectedUsers)
                selectedUsers.removeAll()
                isEditing = false
                UIDevice.feedback(.success)
            }
        } message: {
            if selectedUsers.count == 1, let first = selectedUsers.first {
                Text(L10n.deleteUserSingleConfirmation(first.username))
            } else {
                Text(L10n.deleteUserMultipleConfirmation(selectedUsers.count))
            }
        }
        .errorMessage($viewModel.error)
        .couchPresetEditor(draft: $presetDraft) { draft in
            commitPresetDraft(draft)
        }
    }
}
