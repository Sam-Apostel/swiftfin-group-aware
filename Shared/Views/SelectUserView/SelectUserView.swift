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
    @InjectedObject(\.couchKidsStore)
    private var couchKidsStore

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
    /// The IDs of the kids whose server account has no age limit, for the amber badge.
    @State
    private var kidWithoutLimitUserIDs: Set<String> = []
    /// The servers whose kid flags and user data are being refreshed.
    @State
    private var refreshingKidServerIDs: Set<String> = []
    /// The IDs of the stored users without an access token, who need to sign in again.
    @State
    private var needsSignInUserIDs: Set<String> = []
    /// The IDs of the users who just signed in, to put on the couch once they are loaded.
    @State
    private var pendingCouchAdditionIDs: [String] = []
    /// A server that was just connected to, to open sign-in for once the connect sheet is gone.
    @State
    private var pendingSignInServer: ServerState?
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

    /// The first person gets initial focus on tvOS when nobody is on the couch yet.
    @FocusState
    private var focusedUserID: String?

    @StateObject
    private var memberAuthenticator = CouchMemberAuthenticator()
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

    /// Opens sign-in with the user's name filled in. Signing in replaces the stored
    /// token, for a sign-in that ran out or was revoked by a password change.
    private func signInAgain(_ item: UserItem) {
        UIDevice.impact(.light)
        router.route(to: .userSignIn(server: item.server, username: item.user.username))
    }

    /// Opens sign-in for a server that was just connected to, once the connect sheet is gone.
    ///
    /// Presenting while the connect sheet is still dismissing fails silently, and that
    /// sheet's `onDismiss` clears the new sheet (and on tvOS a route made while a sheet is
    /// still set goes into that sheet). So this waits until no sheet is set, routes, and
    /// checks a moment later that sign-in is still up, trying a few times.
    private func presentPendingSignIn() {
        guard let server = pendingSignInServer else { return }

        Task { @MainActor in
            let coordinator = router.router.navigationCoordinator

            for _ in 0 ..< 6 {
                try? await Task.sleep(for: .milliseconds(600))

                // Replaced by another server, or someone signed in to it already
                guard pendingSignInServer?.id == server.id,
                      !StoredValues[.User.users].contains(where: { $0.serverID == server.id })
                else { return }

                if coordinator?.presentedSheet?.id == "userSignIn" {
                    pendingSignInServer = nil
                    return
                }

                guard coordinator?.presentedSheet == nil, coordinator?.presentedFullScreen == nil else { continue }

                router.route(to: .userSignIn(server: server))
            }

            pendingSignInServer = nil
        }
    }

    private func delete(user: UserState) {
        selectedUsers.insert(user)
        isPresentingConfirmDeleteUsers = true
    }

    /// Deletes the selected users. Deleting a child (`isChildAudience`) loosens kid protection:
    /// the next couch no longer counts as dropping them. So a grown-up confirms first.
    private func deleteSelectedUsers() {
        let users = selectedUsers
        selectedUsers.removeAll()
        isEditing = false

        guard let child = users.first(where: \.isChildAudience) else {
            commitDelete(users)
            return
        }

        // The delete alert is still closing
        memberAuthenticator.didDismissPresentation()

        Task { @MainActor in
            let isConfirmed = await memberAuthenticator.confirmGrownUp(
                grownUps: grownUps(serverID: child.serverID, first: couchSelection),
                authenticationAction: authenticationAction
            )

            guard isConfirmed else { return }

            commitDelete(users)
        }
    }

    private func commitDelete(_ users: Set<UserState>) {
        viewModel.deleteUsers(users)
        UIDevice.feedback(.success)
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

    /// Puts a user who just signed in on the couch, with the same server rule as
    /// `toggleCouch(user:)`. Never takes anyone off the couch.
    private func addToCouch(user: UserState) {
        guard !couchSelection.contains(where: { $0.id == user.id }) else { return }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if let first = couchSelection.first, first.serverID != user.serverID {
                // Couch members must share a server: start a new couch with this user
                couchSelection = [user]
            } else {
                couchSelection.append(user)
            }
        }
    }

    /// Handles `Notifications[.didAddUser]`: a person signed in from this picker.
    private func didAddUser(_ user: UserState) {
        pendingCouchAdditionIDs.append(user.id)

        // A user signing in again is already stored and is added right away,
        // a new user once the reload below has loaded them
        refreshUserFlags()
        applyPendingCouchAdditions()

        viewModel.background.getServers()
    }

    private func applyPendingCouchAdditions() {
        guard pendingCouchAdditionIDs.isNotEmpty else { return }

        let users = storedUsers
        var remainingIDs: [String] = []

        for id in pendingCouchAdditionIDs {
            if let user = users.first(where: { $0.id == id }) {
                addToCouch(user: user)
            } else {
                remainingIDs.append(id)
            }
        }

        pendingCouchAdditionIDs = remainingIDs
    }

    private func refreshUserFlags() {
        let users = storedUsers
        kidUserIDs = Set(users.filter(\.isKid).map(\.id))
        kidWithoutLimitUserIDs = Set(users.filter(\.isKidWithoutServerLimit).map(\.id))
        needsSignInUserIDs = Set(users.filter { $0.storedAccessToken == nil }.map(\.id))
    }

    /// Syncs the household kid flags and the server age limits of the shown users.
    ///
    /// The picker runs signed out, so otherwise synced kid flags only arrive at sign-in.
    private func refreshKidFlags() {
        let shownServerIDs = Set(userItems.map(\.server.id))

        for (server, users) in viewModel.servers where users.isNotEmpty && shownServerIDs.contains(server.id) {
            guard refreshingKidServerIDs.insert(server.id).inserted else { continue }

            Task { @MainActor in
                await UserState.refreshUserData(users, server: server)
                await couchKidsStore.refresh(server: server, users: users)

                refreshingKidServerIDs.remove(server.id)
                refreshUserFlags()
            }
        }
    }

    /// "Mark as kid" never asks. "Unmark as kid" loosens kid protection, so a grown-up confirms first.
    private func toggleKid(user: UserState) {
        guard user.isKid else {
            setKid(true, for: user)
            return
        }

        // The context menu is still closing
        memberAuthenticator.didDismissPresentation()

        Task { @MainActor in
            let isConfirmed = await memberAuthenticator.confirmGrownUp(
                grownUps: grownUps(serverID: user.serverID, first: couchSelection),
                authenticationAction: authenticationAction
            )

            guard isConfirmed else { return }

            setKid(false, for: user)
        }
    }

    private func setKid(_ isKid: Bool, for user: UserState) {
        user.isKid = isKid

        if isKid {
            kidUserIDs.insert(user.id)
        } else {
            kidUserIDs.remove(user.id)
        }

        refreshUserFlags()
        UIDevice.impact(.light)
    }

    /// The stored users of a server for `CouchGrownUpCheck`, the given members first.
    /// The check itself skips restricted users.
    private func grownUps(serverID: String, first members: [UserState]) -> [UserState] {
        let serverUsers = StoredValues[.User.users].filter { $0.serverID == serverID }
        let firstUsers = members.compactMap { member in
            serverUsers.first { $0.id == member.id }
        }
        let firstIDs = Set(firstUsers.map(\.id))

        return firstUsers + serverUsers.filter { !firstIDs.contains($0.id) }
    }

    /// Keeps the couch selection in sync with the stored users and
    /// pre-selects the last couch once the users are first loaded.
    private func syncCouchSelection() {
        let users = storedUsers
        refreshUserFlags()

        if !hasRestoredLastCouch, users.isNotEmpty {
            hasRestoredLastCouch = true
            couchSelection = lastCouch(from: users)

            // A household of one: keep them on the couch, so Start stays one tap
            if couchSelection.isEmpty,
               userItems.count == 1,
               let onlyUser = userItems.first?.user,
               onlyUser.storedAccessToken != nil
            {
                couchSelection = [onlyUser]
            }
        } else {
            // Drop deleted users and pick up renamed users
            couchSelection = couchSelection.compactMap { member in
                users.first { $0.id == member.id }
            }
        }

        applyPendingCouchAdditions()
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

    /// Starts watching as everyone on the couch.
    private func startCouch() {
        startCouch(members: couchSelection)
    }

    /// "Watch as just <name>": puts only this user on the couch and starts.
    private func watchAlone(user: UserState) {
        guard !isStartingCouch else { return }

        UIDevice.impact(.light)

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            couchSelection = [user]
        }

        // The context menu is still closing
        memberAuthenticator.didDismissPresentation()
        startCouch(members: [user])
    }

    /// Confirms each member one at a time (`CouchMemberAuthenticator`), asks a grown-up when
    /// the couch drops a child of the last couch, then signs in as the confirmed members.
    ///
    /// Only the members who actually sign in are recorded as a recent couch.
    private func startCouch(members: [UserState]) {
        guard members.isNotEmpty, !isStartingCouch else { return }

        isStartingCouch = true

        Task { @MainActor in
            defer {
                isStartingCouch = false
            }

            do {
                // Read before signing in, which replaces it
                let lastMemberIDs = Defaults[.Couch.lastMemberIDs]

                let result = try await memberAuthenticator.authenticate(
                    members,
                    authenticationAction: authenticationAction
                )

                // The members that really sign in (same server, a stored token), in pick order
                let storedUsers = StoredValues[.User.users]
                let signInMembers = userSessionManager.couchMembers(
                    for: result.memberIDs,
                    in: storedUsers
                )

                guard let firstMember = signInMembers.first else { return }

                // Dropping a child from the last couch loosens kid protection. A grown-up
                // whose PIN was just checked counts, otherwise ask one.
                if !result.verifiedGrownUp,
                   Self.dropsChild(lastMemberIDs: lastMemberIDs, newMembers: signInMembers, storedUsers: storedUsers)
                {
                    let isConfirmed = await memberAuthenticator.confirmGrownUp(
                        grownUps: grownUps(serverID: firstMember.serverID, first: signInMembers),
                        authenticationAction: authenticationAction
                    )

                    guard isConfirmed else { return }
                }

                let memberIDs = signInMembers.map(\.id)

                try await userSessionManager.signIn(userIDs: memberIDs)
                couchPresetStore.recordRecent(memberIDs: memberIDs)
                UIDevice.feedback(.success)
            } catch is CancellationError {
                return
            } catch {
                await viewModel.error(error)
            }
        }
    }

    /// Whether the last couch on the new couch's server had a child (`isChildAudience`)
    /// and the new couch has none.
    private static func dropsChild(
        lastMemberIDs: [String],
        newMembers: [UserState],
        storedUsers: [UserState]
    ) -> Bool {
        guard let serverID = newMembers.first?.serverID else { return false }

        let lastMembers = lastMemberIDs.compactMap { id in
            storedUsers.first { $0.id == id && $0.serverID == serverID }
        }

        return lastMembers.contains(where: \.isChildAudience) && !newMembers.contains(where: \.isChildAudience)
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
        // An empty name falls back to the members' names ("Sam & Lisa")
        let typedName = CouchPreset.sanitizedName(draft.name)
        let name = typedName.isNotEmpty ? typedName : CouchPreset.sanitizedName(L10n.CouchPresets.members(draft.memberNames))

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

    private var headerSubtitle: String {
        if userItems.isEmpty {
            L10n.CouchPicker.emptySubtitle
        } else if UIDevice.isTV {
            L10n.CouchPicker.subtitleTV
        } else {
            L10n.CouchPicker.subtitle
        }
    }

    @ViewBuilder
    private var headerView: some View {
        if !isEditing {
            VStack(spacing: UIDevice.isTV ? 8 : 4) {
                Text(L10n.CouchPicker.title)
                    .font(UIDevice.isTV ? .title3 : .title2)
                    .fontWeight(.bold)
                    .lineLimit(1)

                Text(headerSubtitle)
                    .font(UIDevice.isTV ? .callout : .subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .frame(maxWidth: UIDevice.isTV ? 900 : 500)
            }
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
                    EmptyUserView(servers: viewModel.servers.keys)
                } else {
                    switch userListDisplayType {
                    case .list:
                        ListView(
                            userItems: userItems,
                            isEditing: $isEditing,
                            selectedUsers: $selectedUsers,
                            couchSelectionIDs: couchSelection.map(\.id),
                            kidUserIDs: kidUserIDs,
                            needsSignInUserIDs: needsSignInUserIDs,
                            serverSelection: serverSelection,
                            servers: viewModel.servers.keys,
                            action: { toggleCouch(user: $0) },
                            onToggleKid: { toggleKid(user: $0) },
                            onSignInAgain: { signInAgain($0) },
                            onDelete: { delete(user: $0) },
                            kidWithoutLimitUserIDs: kidWithoutLimitUserIDs,
                            focusedUserID: $focusedUserID,
                            onWatchAlone: { watchAlone(user: $0) }
                        )

                    case .grid:
                        GridView(
                            userItems: userItems,
                            isEditing: $isEditing,
                            selectedUsers: $selectedUsers,
                            couchSelectionIDs: couchSelection.map(\.id),
                            kidUserIDs: kidUserIDs,
                            needsSignInUserIDs: needsSignInUserIDs,
                            serverSelection: serverSelection,
                            servers: viewModel.servers.keys,
                            action: { toggleCouch(user: $0) },
                            onToggleKid: { toggleKid(user: $0) },
                            onSignInAgain: { signInAgain($0) },
                            onDelete: { delete(user: $0) },
                            kidWithoutLimitUserIDs: kidWithoutLimitUserIDs,
                            focusedUserID: $focusedUserID,
                            onWatchAlone: { watchAlone(user: $0) }
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
        #if os(tvOS)
        // On a common ancestor of the people and the toolbar: with nobody on the couch,
        // the first person gets initial focus (the toolbar defaults to Start otherwise)
        .defaultFocus($focusedUserID, initialFocusedUserID)
        #endif
        .couchMemberAuthenticatorPrompts(memberAuthenticator)
    }

    /// The first person, while nobody is on the couch.
    private var initialFocusedUserID: String? {
        guard !isEditing, couchSelection.isEmpty else { return nil }

        return userItems.first?.user.id
    }

    var body: some View {
        ZStack {
            switch viewModel.state {
            case .initial, .loading:
                ProgressView()
            case .content:
                if viewModel.servers.isEmpty {
                    ConnectToJellyfinView()
                } else if !hasRestoredLastCouch, storedUsers.isNotEmpty {
                    // For one update, until the last couch is restored, so initial focus
                    // goes to Start (or the first person) and not to whatever showed first
                    Color.clear
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
                                isEditing: $isEditing,
                                servers: viewModel.servers.keys
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
            refreshKidFlags()
        }
        .onChange(of: couchKidsStore.revision) {
            refreshUserFlags()
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
            } else if serverSelection == .all, newValue.count == 1, let onlyServer = newValue.first {
                // One server: there is no server menu, and no server name under every person
                let newSelection = SelectUserServerSelection.server(id: onlyServer.id)
                serverSelection = newSelection
                selectUserAllServersSplashscreen = newSelection
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

            // Sign-in opens by itself for a server without people yet, once the
            // connect sheet has finished dismissing
            guard !StoredValues[.User.users].contains(where: { $0.serverID == server.id }) else { return }

            pendingSignInServer = server
            presentPendingSignIn()
        }
        .onNotification(.didAddUser) { user in
            didAddUser(user)
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
                deleteSelectedUsers()
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
