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

/// Couch settings: Browsing, Kids, Grown-up lock (when needed), Languages and It's ready.
///
/// Kid safety rules:
/// - Turning protection off (a kid flag, or Kid-safe browsing) needs a grown-up (`CouchGrownUpCheck`).
///   Turning it on never asks.
/// - "Set age limit…" is sent with an admin's household session, never with the current session
///   (which is the kid's when kid-safe browsing made them the primary).
/// - "Apply now" only makes the couch stricter, closes Settings first and never runs during playback.
struct CouchSettingsView: View {

    /// A change that loosens kid protection: it needs a grown-up first.
    private enum LooseningChange {
        case unmarkKid(UserState)
        case kidSafeBrowsingOff
    }

    /// A change made on this screen that the current couch doesn't follow yet.
    private enum PendingChange {
        /// A member on the couch was marked as a kid, or Kid-safe browsing was turned on.
        case stricter
        /// Anything else: it takes effect the next time a couch starts.
        case other
    }

    @Default(.Couch.kidSafeBrowsing)
    private var kidSafeBrowsing
    @Default(.Couch.hideWatchedByAnyMember)
    private var hideWatchedByAnyMember

    @Environment(\.localUserAuthenticationAction)
    private var authenticationAction

    @InjectedObject(\.userSessionManager)
    private var userSessionManager: UserSessionManager
    @InjectedObject(\.couchKidsStore)
    private var couchKidsStore: CouchKidsStore

    #if os(iOS)
    /// Only read by "Apply now": Couch settings is pushed inside the Settings sheet,
    /// which is presented by a tab's coordinator.
    @EnvironmentObject
    private var tabCoordinator: TabCoordinator
    #endif

    @Router
    private var router

    /// Stored users on the current server, sorted by name.
    @State
    private var users: [UserState] = []

    /// IDs of the users in `users` that are flagged as kids.
    ///
    /// Mirrors `UserState.isKid`, which is not observable.
    @State
    private var kidIDs: Set<String> = []

    /// Bumped when user data (policies) or PINs change, which are not observable.
    @State
    private var storageRevision = 0

    /// Whether the grown-up check is running. The protection toggles are disabled meanwhile.
    @State
    private var isCheckingGrownUp = false

    /// A loosening change waiting for "I'm a grown-up" (no grown-up has a PIN on this device).
    @State
    private var pendingLoosening: LooseningChange?

    @State
    private var pendingChange: PendingChange?

    #if os(iOS)
    /// The "Set age limit…" view model, sending with an admin's session.
    @State
    private var ageLimitViewModel: ServerUserAdminViewModel?
    @State
    private var ageLimitKid: UserState?
    #endif

    // MARK: - Body

    var body: some View {
        Form(systemImage: "sofa.fill") {
            content
        }
        .navigationTitle(L10n.CouchSettings.couchSettings)
        .onAppear {
            loadUsers()
        }
        .task {
            await refreshKids()
        }
        .onChange(of: couchKidsStore.revision) {
            loadUsers()
        }
        .confirmationDialog(
            L10n.GrownUpCheck.confirmationTitle,
            isPresented: isLooseningConfirmationPresented,
            titleVisibility: .visible,
            presenting: pendingLoosening
        ) { change in
            Button(L10n.GrownUpCheck.confirm, role: .destructive) {
                applyLoosening(change)
            }

            Button(L10n.cancel, role: .cancel) {}
        } message: { _ in
            Text(looseningConfirmationMessage)
        }
        #if os(iOS)
        .background {
            ageLimitObserver
        }
        #endif
    }

    @ViewBuilder
    private var content: some View {
        applySection

        browsingSection

        kidsSection

        grownUpLockSection

        CouchLanguagesSection()

        ReadyAlertsSettingsSection()
    }

    // MARK: - Apply Section

    @ViewBuilder
    private var applySection: some View {
        if let pendingChange {
            Section {
                if pendingChange == .stricter, let stricterPrimary = stricterPrimaryTarget {
                    if userSessionManager.hasActivePlayback {
                        Label(L10n.CouchSettings.stopPlaybackToApply, systemImage: "pause.circle")
                            .foregroundStyle(.secondary)
                    } else {
                        Button {
                            applyNow()
                        } label: {
                            Label(
                                L10n.CouchSettings.applyNow(stricterPrimary.username),
                                systemImage: "checkmark.shield.fill"
                            )
                        }
                    }
                } else {
                    Text(L10n.CouchSettings.takesEffectNextCouch)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Browsing Section

    @ViewBuilder
    private var browsingSection: some View {
        Section {
            Toggle(L10n.Couch.kidSafeBrowsing, isOn: kidSafeBrowsingBinding)
                .disabled(isCheckingGrownUp)
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
            if trackedUsers.isEmpty {
                Text(L10n.CouchSettings.noUsers)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(trackedUsers, id: \.id) { user in
                    Toggle(isOn: kidBinding(for: user)) {
                        kidRowLabel(user: user)
                    }
                    .disabled(isCheckingGrownUp)

                    if kidIDs.contains(user.id), user.isKidWithoutServerLimit {
                        noAgeLimitRows(kid: user)
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

    /// The orange "No age limit" warning under a kid, with a way to set one.
    @ViewBuilder
    private func noAgeLimitRows(kid: UserState) -> some View {
        #if os(iOS)
        noAgeLimitRows(kid: kid, adminSession: adminSession)
        #else
        // "Set age limit…" needs the admin dashboard screens, which are iOS only
        noAgeLimitWarning(kid: kid, hint: L10n.CouchSettings.setAgeLimitElsewhere)
        #endif
    }

    #if os(iOS)
    @ViewBuilder
    private func noAgeLimitRows(kid: UserState, adminSession: UserSession?) -> some View {
        if let adminSession, kid.data.policy != nil {
            noAgeLimitWarning(kid: kid, hint: nil)

            Button(L10n.CouchSettings.setAgeLimit) {
                openAgeLimit(kid: kid, adminSession: adminSession)
            }
        } else {
            noAgeLimitWarning(kid: kid, hint: L10n.CouchSettings.setAgeLimitInDashboard)
        }
    }
    #endif

    private func noAgeLimitWarning(kid: UserState, hint: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(L10n.CouchSettings.noAgeLimit(kid.username), systemImage: "exclamationmark.triangle.fill")
                .labelStyle(.sectionFooterWithImage(imageStyle: .orange))

            if let hint {
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Grown-up Lock Section

    @ViewBuilder
    private var grownUpLockSection: some View {
        let children = childUsers
        let pinlessGrownUps = startablePinlessGrownUps

        if children.isNotEmpty, pinlessGrownUps.isNotEmpty {
            let householdSessions = userSessionManager.currentSession?.householdSessions() ?? []

            Section {
                Label(
                    L10n.CouchSettings.grownUpLockWarning(
                        kids: ListFormatter.localizedString(byJoining: children.map(\.username)),
                        device: L10n.GrownUpCheck.deviceName,
                        grownUps: pinlessGrownUps.map(\.username)
                    ),
                    systemImage: "lock.open.fill"
                )
                .labelStyle(.sectionFooterWithImage(imageStyle: .orange))

                ForEach(pinlessGrownUps, id: \.id) { grownUp in
                    if let session = householdSessions.first(where: { $0.user.id == grownUp.id }) {
                        GrownUpPinButton(
                            user: grownUp,
                            onPolicyChange: {
                                storageRevision += 1
                            },
                            action: {
                                router.route(to: .localUserSecurity(userSession: session))
                            }
                        )
                    }
                }
            } header: {
                Text(L10n.CouchSettings.grownUpLock)
            } footer: {
                Text(L10n.CouchSettings.grownUpLockFooter(device: L10n.GrownUpCheck.deviceName))
            }
        }
    }

    /// `users`, read so that the body re-renders on `storageRevision`:
    /// kid flags, policies (age limits) and PINs are not observable.
    private var trackedUsers: [UserState] {
        _ = storageRevision
        return users
    }

    /// The stored users of this server that count as children (`isChildAudience`).
    private var childUsers: [UserState] {
        trackedUsers.filter(\.isChildAudience)
    }

    /// The grown-ups without a PIN on this device that can be started here (they have a stored token).
    private var startablePinlessGrownUps: [UserState] {
        CouchGrownUpCheck.pinlessGrownUps(of: trackedUsers)
            .filter { $0.storedAccessToken != nil }
    }

    private var isGrownUpLockShown: Bool {
        childUsers.isNotEmpty && startablePinlessGrownUps.isNotEmpty
    }

    // MARK: - Bindings

    private var kidSafeBrowsingBinding: Binding<Bool> {
        Binding(
            get: {
                kidSafeBrowsing
            },
            set: { isOn in
                if isOn {
                    kidSafeBrowsing = true
                    notePendingChange(isStricter: true)
                } else {
                    requestLoosening(.kidSafeBrowsingOff)
                }
            }
        )
    }

    private func kidBinding(for user: UserState) -> Binding<Bool> {
        Binding(
            get: {
                kidIDs.contains(user.id)
            },
            set: { isKid in
                if isKid {
                    markKid(user)
                } else {
                    requestLoosening(.unmarkKid(user))
                }
            }
        )
    }

    private var isLooseningConfirmationPresented: Binding<Bool> {
        Binding(
            get: {
                pendingLoosening != nil
            },
            set: { isPresented in
                if !isPresented {
                    // Cancel leaves the toggle on
                    pendingLoosening = nil
                }
            }
        )
    }

    private var looseningConfirmationMessage: String {
        if isGrownUpLockShown {
            return "\(L10n.GrownUpCheck.noPinMessage) \(L10n.CouchSettings.setPinUnderGrownUpLock)"
        }

        return L10n.GrownUpCheck.noPinMessage
    }

    // MARK: - Kid Protection

    /// Marking a kid never asks: it only makes things stricter.
    private func markKid(_ user: UserState) {
        user.isKid = true
        kidIDs.insert(user.id)

        let isOnTheCouch = userSessionManager.currentSession?.couch.memberIDs.contains(user.id) ?? false
        notePendingChange(isStricter: isOnTheCouch)
    }

    /// Asks a grown-up before loosening kid protection. Until then the toggle stays on.
    private func requestLoosening(_ change: LooseningChange) {
        guard !isCheckingGrownUp else {
            // Re-render, so the toggle shows its unchanged value again
            storageRevision += 1
            return
        }

        isCheckingGrownUp = true

        let grownUps = grownUpsForCheck()
        let authenticationAction = authenticationAction

        Task { @MainActor in
            let outcome = await CouchGrownUpCheck.run(
                grownUps: grownUps,
                authenticationAction: authenticationAction
            )

            isCheckingGrownUp = false

            switch outcome {
            case .verified:
                applyLoosening(change)
            case .needsConfirmation:
                pendingLoosening = change
            case .declined:
                // The toggle stays on
                storageRevision += 1
            }
        }
    }

    private func applyLoosening(_ change: LooseningChange) {
        switch change {
        case let .unmarkKid(user):
            user.isKid = false
            kidIDs.remove(user.id)

        case .kidSafeBrowsingOff:
            kidSafeBrowsing = false
        }

        notePendingChange(isStricter: false)
    }

    /// The grown-ups who may approve a loosening change: the couch's grown-ups first,
    /// then the other stored grown-ups of this server. `CouchGrownUpCheck` skips restricted users.
    private func grownUpsForCheck() -> [UserState] {
        let couchGrownUps = userSessionManager.currentSession?.couch.grownUps ?? []
        let couchGrownUpIDs = Set(couchGrownUps.map(\.id))
        let otherGrownUps = users.filter { !couchGrownUpIDs.contains($0.id) && !$0.isRestricted }

        return couchGrownUps + otherGrownUps
    }

    private func notePendingChange(isStricter: Bool) {
        if isStricter {
            pendingChange = .stricter
        } else if pendingChange == nil {
            pendingChange = .other
        }
    }

    // MARK: - Apply Now

    /// The member the current couch would browse as now, when that is stricter than the current primary.
    ///
    /// The same rule as `UserSessionManager.applyStricterPrimaryIfNeeded()`, so "Apply now" is only
    /// shown when it will switch.
    private var stricterPrimaryTarget: UserState? {
        guard let currentSession = userSessionManager.currentSession, currentSession.couch.isGroup else { return nil }

        let orderedIDs = userSessionManager.pickOrderedMemberIDs(of: currentSession.couch)
        let members = userSessionManager.couchMembers(for: orderedIDs, in: StoredValues[.User.users])

        guard let primary = userSessionManager.couchPrimary(of: members),
              primary.id != currentSession.user.id,
              primary.restrictionScore < currentSession.user.restrictionScore
        else { return nil }

        return primary
    }

    /// Closes Settings first (the couch switch rebuilds the tabs), then browses as the stricter member.
    private func applyNow() {
        let userSessionManager = userSessionManager

        closeSettings()

        Task { @MainActor in
            // Let Settings finish closing before the session changes
            try? await Task.sleep(for: .milliseconds(500))

            await userSessionManager.applyStricterPrimaryIfNeeded()
        }
    }

    private func closeSettings() {
        #if os(iOS)
        // `router.dismiss()` would only go back to Settings: close the Settings sheet itself
        if let presenter = tabCoordinator.tabs.first(where: { $0.coordinator.presentedSheet != nil })?.coordinator {
            presenter.presentedSheet = nil
            return
        }
        #endif

        router.dismiss()
    }

    // MARK: - Set Age Limit

    #if os(iOS)
    /// A household session of an administrator (the current session counts too), if this device has one.
    private var adminSession: UserSession? {
        userSessionManager.currentSession?
            .householdSessions()
            .first { $0.user.data.policy?.isAdministrator == true }
    }

    /// Opens the parental rating sheet for `kid`. The policy update is sent with `adminSession`,
    /// not with the current session (which may be the kid's own).
    private func openAgeLimit(kid: UserState, adminSession: UserSession) {
        guard kid.data.policy != nil else { return }

        let viewModel = ServerUserAdminViewModel(user: kid.data)
        viewModel.userSession = adminSession

        ageLimitKid = kid
        ageLimitViewModel = viewModel

        router.route(to: .userParentalRatings(viewModel: viewModel))
    }

    @ViewBuilder
    private var ageLimitObserver: some View {
        if let ageLimitViewModel, let ageLimitKid {
            AgeLimitEventObserver(viewModel: ageLimitViewModel) { policy in
                didUpdateAgeLimit(kid: ageLimitKid, policy: policy)
            }
        }
    }

    /// The sheet saved and closes itself: store the new policy, then refresh the kid's data with their own token.
    private func didUpdateAgeLimit(kid: UserState, policy: UserPolicy?) {
        if let policy {
            kid.data.policy = policy
        }

        ageLimitViewModel = nil
        ageLimitKid = nil
        storageRevision += 1

        guard let server = userSessionManager.currentSession?.server else { return }

        Task { @MainActor in
            await UserState.refreshUserData([kid], server: server)
            storageRevision += 1
        }
    }
    #endif

    // MARK: - Loading

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
        storageRevision += 1
    }

    /// Syncs the household kid flags and refreshes the users' policies (age limits, admins).
    private func refreshKids() async {
        guard let server = userSessionManager.currentSession?.server else { return }

        let serverUsers = StoredValues[.User.users].filter { $0.serverID == server.id }

        await couchKidsStore.refresh(server: server, users: serverUsers)
        await UserState.refreshUserData(serverUsers, server: server)

        loadUsers()
    }
}

// MARK: - Grown-up PIN button

/// "Set a PIN for Sam…". Re-renders Couch settings when that user's sign-in policy changes.
private struct GrownUpPinButton: View {

    @StoredValue
    private var accessPolicy: LocalUserAccessPolicy

    private let user: UserState
    private let onPolicyChange: () -> Void
    private let action: () -> Void

    init(
        user: UserState,
        onPolicyChange: @escaping () -> Void,
        action: @escaping () -> Void
    ) {
        self._accessPolicy = StoredValue(.User.accessPolicy(id: user.id))
        self.user = user
        self.onPolicyChange = onPolicyChange
        self.action = action
    }

    var body: some View {
        ChevronButton(L10n.CouchSettings.setPinFor(user.username), action: action)
            .onChange(of: accessPolicy) {
                onPolicyChange()
            }
    }
}

#if os(iOS)

// MARK: - Age limit event observer

/// Forwards the parental rating sheet's `.updated` event (sent once the policy is saved).
private struct AgeLimitEventObserver: View {

    let viewModel: ServerUserAdminViewModel
    let onUpdated: (UserPolicy?) -> Void

    var body: some View {
        Color.clear
            .onReceive(viewModel.events) { event in
                switch event {
                case .updated:
                    onUpdated(viewModel.user.policy)
                }
            }
    }
}
#endif
