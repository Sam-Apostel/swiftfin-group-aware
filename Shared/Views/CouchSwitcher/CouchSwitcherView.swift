//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import FactoryKit
import Logging
import OrderedCollections
import SwiftUI

/// "Who's on the couch?" while signed in: add people to the couch or take them off,
/// without signing anyone out.
///
/// - Shows the stored users of the current server that have a sign-in, with the current couch
///   selected. "Add person" signs someone new in (`Notifications[.didAddUser]` selects them).
/// - "Update couch" asks only the newly added people for their PIN (`CouchMemberAuthenticator`).
///   A change that loosens kid protection (a restricted person taken off, or browsing as a less
///   restricted person) also asks a grown-up, unless a grown-up just proved it with their PIN.
/// - It submits the current pick order followed by the new people in tap order, so a kid never
///   becomes the first pick. It closes every sheet before it signs in.
///
/// Presented by `NavigationRoute.couchSwitcher`, inside `WithLocalUserAuthentication`.
struct CouchSwitcherView: View {

    /// A cell of the people grid: a person, or the trailing "Add person" tile.
    private enum Cell {
        case user(UserState)
        case addPerson

        var id: String {
            switch self {
            case let .user(user):
                user.id
            case .addPerson:
                "addPerson"
            }
        }
    }

    @Default(.accentColor)
    private var accentColor

    @Environment(\.localUserAuthenticationAction)
    private var authenticationAction
    @Environment(\.couchTabCoordinator)
    private var tabCoordinator

    @InjectedObject(\.userSessionManager)
    private var userSessionManager: UserSessionManager
    @InjectedObject(\.couchKidsStore)
    private var couchKidsStore: CouchKidsStore

    @Router
    private var router

    @StateObject
    private var memberAuthenticator = CouchMemberAuthenticator()

    /// The server of the couch, captured when the switcher opens.
    @State
    private var server: ServerState?
    /// The couch member ids when the switcher opened, in pick order.
    @State
    private var originalIDs: [String] = []
    /// The selected ids, in tap order (the original members first).
    @State
    private var selection: [String] = []
    /// The stored users of the server with a sign-in, sorted by name.
    @State
    private var users: [UserState] = []
    @State
    private var kidUserIDs: Set<String> = []
    @State
    private var kidWithoutLimitUserIDs: Set<String> = []
    /// People who signed in from this switcher: they just proved who they are with their password.
    @State
    private var justSignedInIDs: Set<String> = []
    /// People whose kid flag was changed here: the couch rebuilds to follow it.
    @State
    private var kidChangedIDs: Set<String> = []
    @State
    private var isUpdating = false
    @State
    private var userPendingDeletion: UserState?
    @State
    private var error: Error?

    private let logger = Logger.swiftfin()

    // MARK: - Selection

    private var addedIDs: [String] {
        selection.filter { !originalIDs.contains($0) }
    }

    private var removedIDs: [String] {
        originalIDs.filter { !selection.contains($0) }
    }

    /// The current pick order, then the new people in tap order.
    private var submissionIDs: [String] {
        originalIDs.filter { selection.contains($0) } + addedIDs
    }

    /// Someone was added or taken off, a member signed in again (their member session is rebuilt
    /// with the new sign-in), or a member's kid flag changed.
    private var hasChanges: Bool {
        addedIDs.isNotEmpty
            || removedIDs.isNotEmpty
            || !justSignedInIDs.isDisjoint(with: originalIDs.filter { selection.contains($0) })
            || !kidChangedIDs.isDisjoint(with: selection)
    }

    private var selectedUsers: [UserState] {
        submissionIDs.compactMap { id in
            users.first { $0.id == id }
        }
    }

    private var hasActivePlayback: Bool {
        userSessionManager.hasActivePlayback
    }

    private var cells: [Cell] {
        users.map { Cell.user($0) } + [.addPerson]
    }

    // MARK: - Loading

    private func load() {
        guard let currentSession = userSessionManager.currentSession else { return }

        server = currentSession.server
        originalIDs = userSessionManager.pickOrderedMemberIDs(of: currentSession.couch)
        selection = originalIDs

        loadUsers()
    }

    private func loadUsers() {
        guard let server else { return }

        users = StoredValues[.User.users]
            .filter { $0.serverID == server.id && $0.storedAccessToken != nil }
            .sorted(using: \.username)

        // Drop people who were deleted or lost their sign-in
        let userIDs = Set(users.map(\.id))
        selection = selection.filter { userIDs.contains($0) }

        refreshUserFlags()
    }

    private func refreshUserFlags() {
        kidUserIDs = Set(users.filter(\.isKid).map(\.id))
        kidWithoutLimitUserIDs = Set(users.filter(\.isKidWithoutServerLimit).map(\.id))
    }

    // MARK: - Actions

    private func toggle(_ user: UserState) {
        UIDevice.impact(.light)

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if selection.contains(user.id) {
                selection.removeAll { $0 == user.id }
            } else {
                selection.append(user.id)
            }
        }
    }

    /// Handles `Notifications[.didAddUser]`: someone signed in from "Add person" or "Sign in again".
    private func didAddUser(_ user: UserState) {
        guard let server, user.serverID == server.id else { return }

        justSignedInIDs.insert(user.id)
        loadUsers()

        guard !selection.contains(user.id), users.contains(where: { $0.id == user.id }) else { return }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            selection.append(user.id)
        }
    }

    private func signInAgain(_ user: UserState) {
        guard let server else { return }

        UIDevice.impact(.light)
        router.route(to: .userSignIn(server: server, username: user.username))
    }

    /// "Mark as kid" never asks. "Unmark as kid" loosens kid protection, so a grown-up confirms first.
    private func toggleKid(_ user: UserState) {
        guard user.isKid else {
            setKid(true, for: user)
            return
        }

        // The context menu is still closing
        memberAuthenticator.didDismissPresentation()

        Task { @MainActor in
            let isConfirmed = await memberAuthenticator.confirmGrownUp(
                grownUps: grownUps(first: selectedUsers),
                authenticationAction: authenticationAction
            )

            guard isConfirmed else { return }

            setKid(false, for: user)
        }
    }

    private func setKid(_ isKid: Bool, for user: UserState) {
        user.isKid = isKid
        kidChangedIDs.insert(user.id)

        refreshUserFlags()
        UIDevice.impact(.light)
    }

    /// Someone on the couch can't be deleted while it browses as them: take them off first.
    private func requestDelete(_ user: UserState) {
        guard !originalIDs.contains(user.id) else {
            error = ErrorMessage(L10n.CouchSwitcher.deleteMemberFirst(user.username))
            return
        }

        userPendingDeletion = user
    }

    /// Deleting a child loosens kid protection (the next couch no longer counts as dropping them),
    /// so a grown-up confirms first.
    private func delete(_ user: UserState) {
        // The delete alert is still closing
        memberAuthenticator.didDismissPresentation()

        Task { @MainActor in
            if user.isChildAudience {
                let isConfirmed = await memberAuthenticator.confirmGrownUp(
                    grownUps: grownUps(first: selectedUsers),
                    authenticationAction: authenticationAction
                )

                guard isConfirmed else { return }
            }

            do {
                try user.delete()
            } catch {
                self.error = error
                return
            }

            selection.removeAll { $0 == user.id }
            loadUsers()
            UIDevice.feedback(.success)
        }
    }

    /// The stored users of the server for `CouchGrownUpCheck`, the given people first.
    /// The check itself skips restricted users.
    private func grownUps(first members: [UserState]) -> [UserState] {
        guard let server else { return members }

        let serverUsers = StoredValues[.User.users].filter { $0.serverID == server.id }
        let firstUsers = members.compactMap { member in
            serverUsers.first { $0.id == member.id }
        }
        let firstIDs = Set(firstUsers.map(\.id))

        return firstUsers + serverUsers.filter { !firstIDs.contains($0.id) }
    }

    // MARK: - Update

    /// Whether the new couch loosens kid protection: a restricted person is taken off,
    /// or the couch would browse as someone less restricted than now.
    private func loosensProtection(newMembers: [UserState], storedUsers: [UserState]) -> Bool {
        let newMemberIDs = Set(newMembers.map(\.id))
        let originalMembers = originalIDs.compactMap { id in
            storedUsers.first { $0.id == id }
        }

        if originalMembers.contains(where: { $0.isRestricted && !newMemberIDs.contains($0.id) }) {
            return true
        }

        // Fail closed: without a primary to compare, ask
        guard let newPrimary = userSessionManager.couchPrimary(of: newMembers),
              let currentPrimary = userSessionManager.currentSession?.user
        else { return true }

        return newPrimary.restrictionScore > currentPrimary.restrictionScore
    }

    private func updateCouch() {
        guard !isUpdating else { return }
        guard hasChanges else {
            router.dismiss()
            return
        }
        guard selection.isNotEmpty, !hasActivePlayback else { return }

        isUpdating = true

        Task { @MainActor in
            defer {
                isUpdating = false
            }

            do {
                guard let memberIDs = try await confirmedMemberIDs() else { return }

                closeAndSignIn(memberIDs: memberIDs)
            } catch is CancellationError {
                return
            } catch {
                self.error = error
            }
        }
    }

    /// Confirms the new people and, for a looser couch, a grown-up.
    ///
    /// - Returns: the member ids to sign in, in pick order, or `nil` when a grown-up didn't confirm.
    @MainActor
    private func confirmedMemberIDs() async throws -> [String]? {
        var storedUsers = StoredValues[.User.users]

        // Only new people confirm, and not the ones who just signed in here with their password
        let membersToConfirm = addedIDs
            .filter { !justSignedInIDs.contains($0) }
            .compactMap { id in storedUsers.first { $0.id == id } }

        var confirmedIDs = Set(originalIDs + addedIDs.filter { justSignedInIDs.contains($0) })
        var verifiedGrownUp = false

        if membersToConfirm.isNotEmpty {
            let result = try await memberAuthenticator.authenticate(
                membersToConfirm,
                authenticationAction: authenticationAction
            )

            confirmedIDs.formUnion(result.memberIDs)
            verifiedGrownUp = result.verifiedGrownUp
        }

        // The prompts took a while: read the stored users again (kid flags, sign-ins)
        storedUsers = StoredValues[.User.users]

        let newMembers = userSessionManager.couchMembers(
            for: submissionIDs.filter { confirmedIDs.contains($0) },
            in: storedUsers
        )

        guard newMembers.isNotEmpty else { throw CancellationError() }

        if !verifiedGrownUp, loosensProtection(newMembers: newMembers, storedUsers: storedUsers) {
            let isConfirmed = await memberAuthenticator.confirmGrownUp(
                grownUps: grownUps(first: newMembers),
                authenticationAction: authenticationAction
            )

            guard isConfirmed else { return nil }
        }

        guard !hasActivePlayback else {
            throw ErrorMessage(L10n.CouchSwitcher.stopPlaybackFirst)
        }

        return newMembers.map(\.id)
    }

    /// Closes the switcher and Settings first (the new couch rebuilds the tabs), then signs in.
    private func closeAndSignIn(memberIDs: [String]) {
        let userSessionManager = userSessionManager
        let logger = logger

        if let tabCoordinator {
            tabCoordinator.closeAllPresentedRoutes()
        } else {
            router.dismiss()
        }

        Task { @MainActor in
            // Let the sheets finish closing before the session changes
            try? await Task.sleep(for: .milliseconds(600))

            do {
                guard !userSessionManager.hasActivePlayback else {
                    throw ErrorMessage(L10n.CouchSwitcher.stopPlaybackFirst)
                }

                try await userSessionManager.signIn(userIDs: memberIDs)
                Container.shared.couchPresetStore().recordRecent(memberIDs: memberIDs)
                UIDevice.feedback(.success)
            } catch {
                logger.error(
                    "Couch switcher: unable to change the couch",
                    metadata: ["error": .string(error.localizedDescription)]
                )

                UIDevice.feedback(.error)
                Container.shared
                    .appToastProxy()
                    .present(L10n.CouchSwitcher.couldNotUpdate, systemName: "exclamationmark.triangle")
            }
        }
    }

    // MARK: - Views

    @ViewBuilder
    private func cellView(for cell: Cell, server: ServerState) -> some View {
        switch cell {
        case let .user(user):
            SelectUserView.CouchMemberButton(
                user: user,
                server: server,
                showServer: false,
                isSelected: selection.contains(user.id),
                isDimmed: selection.isNotEmpty && !selection.contains(user.id),
                isKid: kidUserIDs.contains(user.id),
                action: {
                    toggle(user)
                },
                onToggleKid: {
                    toggleKid(user)
                },
                onDelete: {
                    requestDelete(user)
                },
                onSignInAgain: {
                    signInAgain(user)
                },
                isKidWithoutServerLimit: kidWithoutLimitUserIDs.contains(user.id)
            )

        case .addPerson:
            SelectUserView.AddPersonTile(servers: OrderedSet([server]))
        }
    }

    @ViewBuilder
    private func peopleView(server: ServerState) -> some View {
        #if os(tvOS)
        HStack(spacing: EdgeInsets.itemSpacing) {
            ForEach(cells, id: \.id) { cell in
                cellView(for: cell, server: server)
                    .frame(width: 300)
            }
        }
        .edgePadding(.horizontal)
        .focusSection()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scrollIfLargerThanContainer(axes: .horizontal)
        .scrollClipDisabled()
        #else
        CenteredLazyVGrid(
            data: cells,
            id: \.id,
            columns: UIDevice.isPhone ? 2 : 5,
            spacing: EdgeInsets.itemSpacing
        ) { cell in
            cellView(for: cell, server: server)
        }
        .edgePadding(UIDevice.isPhone ? [.horizontal, .vertical] : .horizontal)
        .scrollIfLargerThanContainer(axes: .vertical, padding: 100)
        #endif
    }

    @ViewBuilder
    private var headerView: some View {
        VStack(spacing: UIDevice.isTV ? 8 : 4) {
            #if os(tvOS)
            Text(L10n.CouchSwitcher.title)
                .font(.title3)
                .fontWeight(.bold)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            #endif

            Text(UIDevice.isTV ? L10n.CouchSwitcher.subtitleTV : L10n.CouchSwitcher.subtitle)
                .font(UIDevice.isTV ? .callout : .subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .frame(maxWidth: UIDevice.isTV ? 900 : 500)
        }
        .minimumScaleFactor(0.8)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .edgePadding(.horizontal)
        .padding(.top, UIDevice.isTV ? 40 : 8)
        .padding(.bottom, UIDevice.isTV ? 20 : 8)
    }

    @ViewBuilder
    private func updateButton(server: ServerState) -> some View {
        Button(action: updateCouch) {
            HStack(spacing: UIDevice.isTV ? 24 : 12) {
                if selectedUsers.isNotEmpty {
                    CouchAvatarStack(
                        users: selectedUsers,
                        server: server,
                        size: UIDevice.isTV ? 50 : 30
                    )
                }

                Text(hasActivePlayback ? L10n.CouchSwitcher.stopPlaybackFirst : L10n.CouchSwitcher.updateCouch)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if isUpdating {
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
        // Not disabled while updating: on tvOS a disabled button loses focus,
        // and `updateCouch` already ignores taps while an update is in progress.
        .disabled(selection.isEmpty || hasActivePlayback)
        .frame(height: UIDevice.isTV ? 75 : 50)
        .frame(maxWidth: UIDevice.isTV ? 700 : 480)
        .frame(maxWidth: .infinity)
        .edgePadding([.bottom, .horizontal])
        .focusSection()
    }

    @ViewBuilder
    private func contentView(server: ServerState) -> some View {
        VStack(spacing: 0) {
            headerView

            peopleView(server: server)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .focusSection()

            updateButton(server: server)
        }
        .animation(.linear(duration: 0.1), value: selection)
    }

    var body: some View {
        ZStack {
            if let server {
                contentView(server: server)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(UIDevice.isTV ? "" : L10n.CouchSwitcher.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarCloseButton {
            router.dismiss()
        }
        .couchMemberAuthenticatorPrompts(memberAuthenticator)
        .onFirstAppear {
            load()
        }
        .onChange(of: couchKidsStore.revision) {
            refreshUserFlags()
        }
        .onNotification(.didAddUser) { user in
            didAddUser(user)
        }
        .alert(
            L10n.delete,
            isPresented: Binding(
                get: { userPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        userPendingDeletion = nil
                    }
                }
            ),
            presenting: userPendingDeletion
        ) { user in
            Button(L10n.delete, role: .destructive) {
                delete(user)
            }

            Button(L10n.cancel, role: .cancel) {}
        } message: { user in
            Text(L10n.deleteUserSingleConfirmation(user.username))
        }
        .errorMessage($error)
    }
}
