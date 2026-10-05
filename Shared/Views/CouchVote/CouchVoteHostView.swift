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

/// "Vote for tonight", host side (usually the TV).
///
/// 1. Pick 3, 4 or 5 of the decider's upcoming cards and send them to everyone's phone.
/// 2. Watch the live tally; vote on the TV for anyone without a phone ("Vote as…").
/// 3. The winner is revealed with the decider's slot reel, ready to **Watch**.
///
/// Leaving the screen while the vote is open cancels it on every phone.
struct CouchVoteHostView: View {

    private let couch: CouchGroup
    private let candidates: [CouchDeciderCandidate]
    private let items: [String: BaseItemDto]
    private let session: UserSession?

    init(
        couch: CouchGroup,
        candidates: [CouchDeciderCandidate],
        items: [String: BaseItemDto]
    ) {
        self.couch = couch
        self.candidates = candidates
        self.items = items
        self.session = Container.shared.currentUserSession()
    }

    var body: some View {
        if let session {
            Content(
                couch: couch,
                candidates: candidates,
                items: items,
                session: session
            )
        } else {
            NotSignedInView()
        }
    }
}

// MARK: - Focus

extension CouchVoteHostView {

    enum FocusField: Hashable {
        case option(String)
        case optionCount(Int)
        case send
        case watch
    }
}

// MARK: - Not signed in

extension CouchVoteHostView {

    private struct NotSignedInView: View {

        @Router
        private var router

        var body: some View {
            VStack(spacing: UIDevice.isTV ? 40 : 20) {
                ContentUnavailableView(
                    L10n.CouchVote.notSignedIn,
                    systemImage: "hand.raised.slash"
                )

                Button(L10n.close) {
                    router.dismiss()
                }
                .backport
                .buttonStyle(.glass)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Content

extension CouchVoteHostView {

    struct Content: View {

        @Default(.accentColor)
        private var accentColor

        @Router
        private var router

        @StateObject
        private var host: CouchVoteHost

        @FocusState
        private var focusedField: FocusField?

        @State
        private var optionCount: Int
        @State
        private var voteAsOption: CouchVoteOption?
        @State
        private var isCancelConfirmationPresented = false
        @State
        private var hasLanded = false
        @State
        private var isResolvingPlayback = false
        @State
        private var isDismissing = false
        @State
        private var error: Error?

        private let couch: CouchGroup
        private let candidates: [CouchDeciderCandidate]
        private let items: [String: BaseItemDto]
        private let session: UserSession

        init(
            couch: CouchGroup,
            candidates: [CouchDeciderCandidate],
            items: [String: BaseItemDto],
            session: UserSession
        ) {
            self.couch = couch
            self.candidates = Array(candidates.prefix(5))
            self.items = items
            self.session = session

            self._host = StateObject(wrappedValue: CouchVoteHost(couch: couch, primary: session))
            self._optionCount = State(initialValue: min(4, candidates.count))
        }

        // MARK: - Derived

        /// The counts offered before sending: 3 · 4 · 5, capped by the number of candidates.
        private var optionCountChoices: [Int] {
            [3, 4, 5].filter { $0 <= candidates.count }
        }

        /// The options as they will be sent (before start) or as they were sent (after).
        private var options: [CouchVoteOption] {
            if let poll = host.poll {
                return poll.options
            }

            return candidates
                .prefix(max(optionCount, 0))
                .map { CouchVoteOption(candidate: $0, item: items[$0.id]) }
        }

        private var isVoteActive: Bool {
            host.phase == .starting || host.phase == .open
        }

        private var isSetup: Bool {
            host.phase == .idle
        }

        private var winnerOptionID: String? {
            if case let .closed(winnerOptionID) = host.phase {
                return winnerOptionID
            }

            return nil
        }

        private var isClosed: Bool {
            if case .closed = host.phase {
                return true
            }

            return false
        }

        private var showsUnreachableBanner: Bool {
            host.phase == .open && host.phoneMemberIDs.isEmpty && hasPhoneCapableMember
        }

        /// The art behind everything: the winner, else the current favourite, else the first option.
        private var backgroundItem: BaseItemDto? {
            let id = winnerOptionID
                ?? host.tally.leadingOptionIDs.first(where: { host.tally.count(for: $0) > 0 })
                ?? options.first?.id

            return id.flatMap { items[$0] }
        }

        private func voters(for optionID: String) -> [UserState] {
            let ids = host.tally.votersByOptionID[optionID] ?? []
            return couch.members.filter { ids.contains($0.id) }
        }

        func memberStatus(_ member: UserState) -> MemberStatus? {
            guard !isSetup else { return nil }

            if host.tally.votedUserIDs.contains(member.id) {
                return .voted
            }
            if host.elsewhereMemberIDs.contains(member.id) {
                return .elsewhere
            }
            if host.unreachableMemberIDs.contains(member.id) {
                return .unreachable
            }
            if host.hostOnlyMemberIDs.contains(member.id) {
                return .votesHere
            }
            if host.presentMemberIDs.contains(member.id) {
                return .phone
            }
            if host.waitingMemberIDs.contains(member.id) {
                return .waiting
            }

            // Phone members whose phone didn't pick the vote up in time vote here (a late pickup flips them back)
            return host.phase == .starting ? nil : .votesHere
        }

        /// The couch for "Vote as…": who votes here first, then who may still vote on a phone,
        /// then who can't be reached, then who already voted. Couch order within each group.
        private var voteAsMembers: [UserState] {
            couch.members
                .enumerated()
                .sorted { lhs, rhs in
                    let lhsRank = memberStatus(lhs.element)?.voteAsRank ?? 0
                    let rhsRank = memberStatus(rhs.element)?.voteAsRank ?? 0

                    return lhsRank == rhsRank ? lhs.offset < rhs.offset : lhsRank < rhsRank
                }
                .map(\.element)
        }

        /// "Sam", or for someone who already voted "Sam ✓ (on phone)" / "Lisa ✓ (Toy Story)".
        private func voteAsTitle(_ member: UserState) -> String {
            guard host.tally.votedUserIDs.contains(member.id) else { return member.username }
            guard let hostChoice = host.hostCastChoice(of: member.id) else {
                return L10n.CouchVote.votedOnPhone(member.username)
            }

            let choiceTitle = hostChoice.optionID
                .flatMap { optionID in options.first { $0.id == optionID }?.title }
                ?? L10n.CouchVote.anythingsFine

            return L10n.CouchVote.votedHere(member.username, choiceTitle)
        }

        /// Whether anyone on the couch could vote on a phone (kids never do).
        private var hasPhoneCapableMember: Bool {
            couch.members.contains { !$0.isChildAudience }
        }

        // MARK: - Actions

        private func send() {
            let options = self.options
            guard options.count >= 2 else { return }

            UIDevice.impact(.light)

            Task {
                await host.start(options: options)
            }
        }

        private func castVote(userID: String, optionID: String) {
            UIDevice.impact(.light)
            host.castOnHost(userID: userID, optionID: optionID)
        }

        private func closeNow() {
            Task {
                await host.closeNow()
            }
        }

        private func cancelAndDismiss() {
            guard !isDismissing else { return }

            isDismissing = true

            if isVoteActive {
                // Leave right away: the cancel write finishes in the background. Waiting for it
                // froze the screen on a slow account, and a Menu press meanwhile (no exit handler
                // once the phase is `.cancelled`) closed the screen, so the late dismiss closed the decider too.
                let host = self.host

                Task { @MainActor in
                    await host.cancel()
                    host.stop()
                }
            } else {
                host.stop()
            }

            router.dismiss()
        }

        private func dismissAfterReveal() {
            guard !isDismissing else { return }

            isDismissing = true
            host.stop()
            router.dismiss()
        }

        private func watch() {
            guard hasLanded,
                  !isResolvingPlayback,
                  let winnerOptionID,
                  let item = items[winnerOptionID]
            else { return }

            isResolvingPlayback = true

            Task {
                defer {
                    isResolvingPlayback = false
                }

                do {
                    let playbackItem = try await CouchDeciderPlayback.playbackItem(
                        for: item,
                        session: session
                    )

                    // Building the route registers the player manager: route right away.
                    if let route = CouchDeciderPlayback.route(
                        for: playbackItem,
                        session: session
                    ) {
                        router.route(to: route)
                    }
                } catch {
                    self.error = error
                }
            }
        }

        private func onPhaseChanged() {
            switch host.phase {
            case .open:
                if let firstID = options.first?.id {
                    focusedField = .option(firstID)
                }

            case .idle, .starting, .closed, .cancelled:
                break
            }
        }

        private func onLanded() {
            // The reel plays its own landing haptic
            guard !hasLanded else { return }

            withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) {
                hasLanded = true
            }

            focusedField = .watch
        }

        // MARK: - Header

        @ViewBuilder
        private var countdown: some View {
            if host.phase == .open, let poll = host.poll {
                Label {
                    Text(
                        timerInterval: min(poll.createdAt, poll.deadline) ... poll.deadline,
                        countsDown: true
                    )
                    .monospacedDigit()
                } icon: {
                    Image(systemName: "timer")
                }
                .font(UIDevice.isTV ? .headline : .subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            }
        }

        @ViewBuilder
        private var header: some View {
            VStack(spacing: UIDevice.isTV ? 24 : 12) {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(L10n.CouchVote.voteForTonight)
                        .font(UIDevice.isTV ? .title2 : .title2)
                        .fontWeight(.bold)
                        .lineLimit(1)

                    countdown
                }

                MemberStrip(
                    members: couch.members,
                    server: session.server,
                    status: memberStatus
                )
                .animation(.linear(duration: 0.2), value: host.tally)
            }
            .frame(maxWidth: .infinity)
        }

        // MARK: - Banner

        @ViewBuilder
        private var unreachableBanner: some View {
            if showsUnreachableBanner {
                Label(L10n.CouchVote.phonesUnreachable, systemImage: "iphone.slash")
                    .font(UIDevice.isTV ? .callout : .footnote)
                    .fontWeight(.semibold)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, UIDevice.isTV ? 30 : 14)
                    .padding(.vertical, UIDevice.isTV ? 14 : 8)
                    .backport
                    .glassEffect(.regular, in: .capsule)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }

        // MARK: - Phases

        @ViewBuilder
        private var phaseContent: some View {
            if isClosed {
                WinnerReveal(
                    options: options,
                    items: items,
                    winnerOptionID: winnerOptionID,
                    tiedOptionIDs: host.tally.leadingOptionIDs,
                    winnerVoters: winnerOptionID.map(voters(for:)) ?? [],
                    winnerVoteCount: winnerOptionID.map { host.tally.count(for: $0) } ?? 0,
                    server: session.server,
                    hasLanded: hasLanded,
                    isResolvingPlayback: isResolvingPlayback,
                    focusedField: $focusedField,
                    onLanded: onLanded,
                    onWatch: watch,
                    onBack: dismissAfterReveal
                )
                .transition(.opacity)
            } else {
                VStack(spacing: UIDevice.isTV ? 40 : 16) {
                    unreachableBanner

                    openHint

                    optionsSection

                    footer
                }
                .transition(.opacity)
            }
        }

        /// How to join from a phone (or, when no phone can join, how to vote here).
        /// Above the options: on tvOS the scroll view only follows focus, so a hint below them stays off screen.
        @ViewBuilder
        private var openHint: some View {
            if host.phase == .open {
                Text(host.phoneMemberIDs.isEmpty ? L10n.CouchVote.hostVoteHint : L10n.CouchVote.joinHint)
                    .font(UIDevice.isTV ? .callout : .footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
        }

        @ViewBuilder
        private var optionsSection: some View {
            OptionList(
                options: options,
                items: items,
                tally: host.tally,
                isLive: host.phase == .open,
                server: session.server,
                voters: voters(for:),
                focusedField: $focusedField
            ) { option in
                voteAsOption = option
            }
            .opacity(host.phase == .starting ? 0.6 : 1)
            .disabled(host.phase != .open)
        }

        @ViewBuilder
        private var footer: some View {
            switch host.phase {
            case .idle:
                setupFooter

            case .starting:
                HStack(spacing: 12) {
                    ProgressView()

                    Text(L10n.CouchVote.startingVote)
                        .font(UIDevice.isTV ? .headline : .subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(height: UIDevice.isTV ? 75 : 50)

            case .open:
                openFooter

            case .closed, .cancelled:
                EmptyView()
            }
        }

        // MARK: - Body

        @ViewBuilder
        private var background: some View {
            ZStack {
                Color.black

                if let backgroundItem {
                    Color.clear
                        .overlay {
                            PosterImage(
                                item: backgroundItem,
                                type: .landscape,
                                size: .medium
                            )
                        }
                        .clipped()
                        .blur(radius: UIDevice.isTV ? 60 : 40)
                        .opacity(0.55)
                        .id(backgroundItem.id)
                        .transition(.opacity)
                }

                LinearGradient(
                    colors: [.black.opacity(0.2), .black.opacity(0.75)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .animation(.easeInOut(duration: 0.6), value: backgroundItem?.id)
            .ignoresSafeArea()
            .accessibilityHidden(true)
        }

        @ViewBuilder
        private var content: some View {
            ScrollView(.vertical) {
                VStack(spacing: UIDevice.isTV ? 50 : 24) {
                    header

                    phaseContent
                }
                .padding(.vertical, UIDevice.isTV ? 40 : 16)
                .edgePadding(.horizontal)
                .frame(maxWidth: .infinity)
            }
            .scrollClipDisabled()
            .scrollIndicators(.hidden)
        }

        var body: some View {
            ZStack {
                background

                content
            }
            #if os(iOS)
            .overlay(alignment: .topLeading) {
                    if !isClosed {
                        closeButton
                    }
                }
            #endif
                .environment(\.colorScheme, .dark)
            .animation(.easeInOut(duration: 0.3), value: host.phase)
            .animation(.easeInOut(duration: 0.3), value: showsUnreachableBanner)
            .defaultFocus($focusedField, defaultFocus)
            #if os(tvOS)
            .onExitCommand(perform: isVoteActive ? { isCancelConfirmationPresented = true } : nil)
            .onPlayPauseCommand(perform: isClosed && hasLanded ? { watch() } : nil)
            #endif
            .onChange(of: host.phase) {
                onPhaseChanged()
            }
            .confirmationDialog(
                L10n.CouchVote.cancelVoteConfirm,
                isPresented: $isCancelConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button(L10n.CouchVote.cancelVote, role: .destructive) {
                    cancelAndDismiss()
                }

                Button(L10n.CouchVote.keepVoting, role: .cancel) {}
            }
            .confirmationDialog(
                L10n.CouchVote.voteAs,
                isPresented: isVoteAsPresented,
                titleVisibility: .visible,
                presenting: voteAsOption
            ) { option in
                ForEach(voteAsMembers) { member in
                    Button(voteAsTitle(member)) {
                        castVote(userID: member.id, optionID: option.id)
                    }
                }

                Button(L10n.cancel, role: .cancel) {}
            } message: { option in
                Text(option.title)
            }
            .errorMessage($error)
            .onFinalDisappear { [host = self.host] in
                // The screen is gone (Menu, swipe, sign-out): never leave phones prompting.
                Task { @MainActor in
                    if host.phase == .starting || host.phase == .open {
                        await host.cancel()
                    }

                    host.stop()
                }
            }
        }

        private var isVoteAsPresented: Binding<Bool> {
            Binding(
                get: { voteAsOption != nil },
                set: { isPresented in
                    if !isPresented {
                        voteAsOption = nil
                    }
                }
            )
        }

        private var defaultFocus: FocusField? {
            switch host.phase {
            case .idle:
                .send
            case .starting, .open:
                options.first.map { .option($0.id) }
            case .closed:
                hasLanded ? .watch : nil
            case .cancelled:
                nil
            }
        }

        #if os(iOS)
        @ViewBuilder
        private var closeButton: some View {
            Button {
                if isVoteActive {
                    isCancelConfirmationPresented = true
                } else {
                    cancelAndDismiss()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .backport
            .glassEffect(.regular.interactive(), in: .circle)
            .padding(.leading, EdgeInsets.edgePadding)
            .padding(.top, 4)
            .accessibilityLabel(L10n.close)
        }
        #endif

        // MARK: - Footers

        @ViewBuilder
        private var setupFooter: some View {
            VStack(spacing: UIDevice.isTV ? 30 : 16) {
                if optionCountChoices.count > 1 {
                    VStack(spacing: UIDevice.isTV ? 16 : 8) {
                        Text(L10n.CouchVote.howManyOptions)
                            .font(UIDevice.isTV ? .headline : .subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)

                        HStack(spacing: UIDevice.isTV ? 20 : 8) {
                            ForEach(optionCountChoices, id: \.self) { count in
                                Button(L10n.CouchVote.optionCount(count)) {
                                    UIDevice.impact(.light)
                                    optionCount = count
                                }
                                .isSelected(optionCount == count)
                                .focused($focusedField, equals: .optionCount(count))
                            }
                        }
                        .buttonStyle(.capsule(selectionTint: accentColor, focusTint: UIDevice.isTV ? .white : nil))
                        .controlSize(UIDevice.isTV ? .large : .regular)
                        .focusSection()
                    }
                }

                HStack(spacing: UIDevice.isTV ? 40 : 12) {
                    Button {
                        send()
                    } label: {
                        Label(L10n.CouchVote.startVote, systemImage: "paperplane.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .fontWeight(.semibold)
                    .backport
                    .buttonStyle(.glassProminent.shadow(false))
                    .tint(accentColor)
                    #if os(iOS)
                    .controlSize(.large)
                    #endif
                    .frame(height: UIDevice.isTV ? 75 : 50)
                    .frame(maxWidth: UIDevice.isTV ? 500 : .infinity)
                    .focused($focusedField, equals: .send)
                    .disabled(options.count < 2)
                }
                .focusSection()
            }
        }

        @ViewBuilder
        private var openFooter: some View {
            VStack(spacing: UIDevice.isTV ? 30 : 16) {
                HStack(spacing: UIDevice.isTV ? 40 : 12) {
                    Button {
                        closeNow()
                    } label: {
                        Label(L10n.CouchVote.closeVoteNow, systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .fontWeight(.semibold)
                    .backport
                    .buttonStyle(.glassProminent.shadow(false))
                    .tint(accentColor)
                    #if os(iOS)
                    .controlSize(.large)
                    #endif
                    .frame(height: UIDevice.isTV ? 75 : 50)
                    .frame(maxWidth: UIDevice.isTV ? 450 : .infinity)

                    Button(role: .destructive) {
                        isCancelConfirmationPresented = true
                    } label: {
                        Label(L10n.CouchVote.cancelVote, systemImage: "xmark")
                            .frame(maxWidth: .infinity)
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(.red)
                    .backport
                    .buttonStyle(.glass)
                    #if os(iOS)
                    .controlSize(.large)
                    #endif
                    .frame(height: UIDevice.isTV ? 75 : 50)
                    .frame(maxWidth: UIDevice.isTV ? 450 : .infinity)
                }
                .focusSection()
            }
        }
    }
}
