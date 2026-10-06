//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import JellyfinAPI
import SwiftUI

/// "What should we watch?": one title at a time from the couch's candidates.
///
/// The view model does one thing per action and bumps `cardGeneration` when the card changes.
/// All animation (reel, flip, drop, swipe) lives here: before calling the view model, an action
/// records which animation should play (`pendingAnimation`), and `cardDidChange()` plays it.
/// Pressing any button mid-animation first skips to the landing.
struct CouchDeciderView: View {

    /// How the next card change animates.
    enum CardAnimation: Equatable {
        /// A slot-machine reel that lands on the new card.
        case reel(duration: TimeInterval)
        /// A 3D card flip (Shuffle).
        case flip
        /// The card drops and fades, then the next one flips in (Not tonight).
        case drop
        /// The next card scales in (after an iPhone swipe flew the old one off screen).
        case appear
        /// A plain crossfade.
        case crossfade
    }

    @Default(.accentColor)
    private var accentColor

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    @FocusState
    private var focusedAction: DeciderAction?

    @Router
    private var router

    @StateObject
    private var viewModel: CouchDeciderViewModel
    @StateObject
    private var toastProxy = ToastProxy()

    // MARK: Card animation state

    /// The candidate the card shows. Lags `viewModel.current` while an animation runs.
    @State
    private var displayedID: String?
    @State
    private var pendingAnimation: CardAnimation = .reel(duration: 1.6)
    @State
    private var animationTask: Task<Void, Never>?

    @State
    private var isReeling = false
    @State
    private var reelSpinID = 0
    @State
    private var reelDuration: TimeInterval = 1.6
    @State
    private var reelItems: [BaseItemDto] = []
    @State
    private var isInfoVisible = true

    /// Whether the filter row offers "Undo" (for a few seconds after "Not tonight").
    @State
    private var isUndoOffered = false
    @State
    private var undoTask: Task<Void, Never>?

    @State
    private var flipAngle: Double = 0
    @State
    private var dropOffset: CGFloat = 0
    @State
    private var cardOpacity: Double = 1
    @State
    private var cardScale: CGFloat = 1
    @State
    private var cardTilt: Double = 0

    #if os(iOS)
    @State
    private var dragOffset: CGFloat = 0
    @State
    private var isDragging = false
    @State
    private var swipeCount = 0
    #endif

    init(couch: CouchGroup) {
        _viewModel = StateObject(wrappedValue: CouchDeciderViewModel(couch: couch))
    }

    // MARK: - Derived

    private var displayedCandidate: CouchDeciderCandidate? {
        guard let displayedID else { return nil }

        if viewModel.current?.id == displayedID {
            return viewModel.current
        }

        return viewModel.pool.candidates.first { $0.id == displayedID }
    }

    private var displayedItem: BaseItemDto? {
        displayedID.flatMap { viewModel.item(for: $0) }
    }

    private var isResolving: Bool {
        viewModel.background.is(.resolving)
    }

    private var headerTitle: String {
        if viewModel.couch.isGroup {
            return L10n.CouchDecider.tonightFor(viewModel.couch.displayNames)
        }

        return L10n.CouchDecider.tonightForYou
    }

    /// "Undo" right after "Not tonight", then "Hidden: N" while titles are hidden.
    private var hiddenChip: HiddenChip? {
        if isUndoOffered, viewModel.canUndoNotTonight {
            return .undo
        }

        if viewModel.excludedCount > 0 {
            return .hidden(count: viewModel.excludedCount)
        }

        return nil
    }

    private var isHeaderVoteVisible: Bool {
        viewModel.state == .content && viewModel.current != nil && Self.isVoteAvailable(viewModel)
    }

    // MARK: - Body

    var body: some View {
        OverlayToastView(proxy: toastProxy) {
            ZStack {
                backgroundView

                VStack(spacing: UIDevice.isTV ? 30 : 12) {
                    header

                    stateView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                #if os(iOS)
                .padding(.vertical, 8)
                #endif
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.state)
        .colorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .onFirstAppear {
            pendingAnimation = .reel(duration: 1.6)
            viewModel.load()
        }
        .onDisappear {
            skipToLanding()
            hideUndo()
        }
        .onChange(of: viewModel.cardGeneration) { _, _ in
            cardDidChange()
        }
        .onChange(of: viewModel.notTonightGeneration) { _, _ in
            offerUndo()
        }
        .onChange(of: viewModel.state) { _, newState in
            focusWatchIfNeeded(for: newState)
        }
        .onReceive(viewModel.events) { event in
            switch event {
            case let .play(item):
                play(item)
            case let .failed(message):
                toastProxy.present(message, systemName: "exclamationmark.circle.fill")
            }
        }
        #if os(tvOS)
        .onPlayPauseCommand(perform: watch)
        #endif
        #if os(iOS)
        .preference(key: PresentationControllerShouldDismissPreferenceKey.self, value: !isDragging)
        #endif
    }

    // MARK: - Background

    /// The current card's landscape art, heavily blurred and dimmed, crossfading as the card changes.
    private var backgroundView: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black

                if let displayedItem {
                    PosterImage(item: displayedItem, type: .landscape, size: .medium)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .blur(radius: UIDevice.isTV ? 60 : 40)
                        .opacity(0.55)
                        .id(displayedItem.id)
                        .transition(.opacity)
                }

                LinearGradient(
                    colors: [.black.opacity(0.25), .black.opacity(0.75)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .animation(.easeInOut(duration: 0.6), value: displayedID)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: UIDevice.isTV ? 12 : 6) {
                Text(headerTitle)
                    .font(UIDevice.isTV ? .title3 : .title2)
                    .fontWeight(.bold)
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)

                kidSafetyBadge
            }

            Spacer(minLength: 0)

            #if os(iOS)
            if isHeaderVoteVisible {
                voteCapsule
            }

            Button {
                router.dismiss()
            } label: {
                Label(L10n.close, systemImage: "xmark")
                    .labelStyle(.iconOnly)
                    .font(.body)
                    .fontWeight(.semibold)
                    .frame(width: 44, height: 44)
            }
            .foregroundStyle(.primary, .secondary)
            .buttonStyle(.borderless)
            .buttonBorderShape(.circle)
            .backport
            .glassEffect(.regular.interactive(), in: .circle)
            #endif
        }
        .edgePadding(.horizontal)
    }

    #if os(iOS)
    /// "Let everyone vote" as a labelled capsule next to Close.
    private var voteCapsule: some View {
        Button(action: startVote) {
            Label(L10n.CouchDecider.vote, systemImage: "hand.raised")
                .labelStyle(.titleAndIcon)
                .font(.body)
                .fontWeight(.semibold)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .frame(height: 44)
        }
        .foregroundStyle(.primary, .secondary)
        .buttonStyle(.borderless)
        .buttonBorderShape(.capsule)
        .backport
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityHint(L10n.CouchVote.letEveryoneVote)
    }
    #endif

    @ViewBuilder
    private var kidSafetyBadge: some View {
        switch viewModel.pool.kidSafety {
        case .notNeeded:
            EmptyView()

        case let .verified(names):
            kidSafetyLabel(
                L10n.CouchDecider.kidSafeFor(Self.joined(names)),
                systemImage: "checkmark.shield.fill",
                color: .green
            )

        case let .localOnly(names):
            kidSafetyLabel(
                L10n.CouchDecider.kidSafeLocalOnly(Self.joined(names)),
                systemImage: "exclamationmark.shield.fill",
                color: .orange
            )

        case let .limitedToPicks(names):
            kidSafetyLabel(
                L10n.CouchDecider.onlyPicksFor(Self.joined(names)),
                systemImage: "exclamationmark.shield.fill",
                color: .orange
            )
        }
    }

    private static func joined(_ names: [String]) -> String {
        ListFormatter.localizedString(byJoining: names)
    }

    private func kidSafetyLabel(_ title: String, systemImage: String, color: Color) -> some View {
        Label {
            Text(title)
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(color)
        }
        .font(UIDevice.isTV ? .caption : .footnote)
        .fontWeight(.semibold)
        // The orange badge is long, and on iPhone shares the row with Vote and Close
        .lineLimit(UIDevice.isTV ? 2 : 3)
        .padding(.horizontal, UIDevice.isTV ? 16 : 10)
        .padding(.vertical, UIDevice.isTV ? 8 : 5)
        .background(.ultraThinMaterial, in: .capsule)
    }

    // MARK: - States

    @ViewBuilder
    private var stateView: some View {
        switch viewModel.state {
        case .initial, .loading:
            loadingView

        case .content:
            if viewModel.pool.candidates.isEmpty {
                emptyPoolView
            } else {
                deciderView
            }

        case .error:
            if let error = viewModel.error {
                // `.refreshable` only here: on the whole screen, the horizontal filter row would
                // inherit it on iOS, and pulling down on the chips would reload the deck.
                ErrorView(error: error)
                    .refreshable {
                        pendingAnimation = .reel(duration: 1.6)
                        await viewModel.load()
                    }
            } else {
                loadingView
            }
        }
    }

    /// The reel spinning on placeholder cards.
    private var loadingView: some View {
        VStack(spacing: UIDevice.isTV ? 40 : 20) {
            CouchDeciderSlotReel(items: [], landingItemID: nil, spinID: 0)
                .frame(maxHeight: UIDevice.isTV ? 560 : 380)
                .shadow(color: .black.opacity(0.4), radius: 20, y: 10)

            Text(L10n.CouchDecider.lookingAtWhatYouHave)
                .font(UIDevice.isTV ? .headline : .subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
        }
        .edgePadding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Nothing to suggest: Retry when a restricted member's account couldn't be checked, otherwise Browse.
    @ViewBuilder
    private var emptyPoolView: some View {
        if case let .limitedToPicks(names) = viewModel.pool.kidSafety {
            ContentUnavailableView {
                Label(
                    L10n.CouchDecider.couldNotCheckAccount(Self.joined(names)),
                    systemImage: "person.crop.circle.badge.exclamationmark"
                )
            } description: {
                Text(L10n.CouchDecider.couldNotCheckAccountHint)
            } actions: {
                Button(action: retry) {
                    Text(L10n.retry)
                }
                .backport
                .buttonStyle(.glassProminent.shadow(false))
                .tint(accentColor)
            }
            .focusSection()
        } else {
            ContentUnavailableView {
                Label(L10n.CouchDecider.nothingToSuggest, systemImage: "dice")
            } description: {
                Text(LocalizedStringKey(emptyPoolHint))
            } actions: {
                Button {
                    router.dismiss()
                } label: {
                    Text(L10n.CouchDecider.browse)
                }
                .backport
                .buttonStyle(.glassProminent.shadow(false))
                .tint(accentColor)
            }
            .focusSection()
        }
    }

    /// Says so when the rating ceiling for kids without a parental rating emptied the pool.
    private var emptyPoolHint: String {
        if case let .localOnly(names) = viewModel.pool.kidSafety, viewModel.pool.removedByKidCeiling > 0 {
            return L10n.CouchDecider.nothingRatedFor(Self.joined(names))
        }

        return L10n.CouchDecider.nothingToSuggestHint
    }

    @ViewBuilder
    private var deciderView: some View {
        VStack(spacing: UIDevice.isTV ? 30 : 12) {
            CouchDeciderView.FilterBar(
                filters: viewModel.filters,
                genreChips: viewModel.genreChips,
                hiddenChip: hiddenChip,
                onUndo: undoNotTonight,
                onRestoreHidden: resetExclusions,
                onChange: setFilters
            )

            if viewModel.current == nil {
                noMatchView
            } else {
                #if os(tvOS)
                tvCardLayout
                #else
                phoneCardLayout
                #endif
            }
        }
    }

    /// "Nothing matches": Clear filters, plus Bring back N when titles were hidden with Not tonight.
    private var noMatchView: some View {
        ContentUnavailableView {
            Label(L10n.CouchDecider.nothingMatches, systemImage: "line.3.horizontal.decrease.circle")
        } actions: {
            if !viewModel.filters.isDefault {
                Button {
                    setFilters(CouchDeciderFilters())
                } label: {
                    Text(L10n.CouchDecider.clearFilters)
                }
                .backport
                .buttonStyle(.glassProminent.shadow(false))
                .tint(accentColor)
            }

            if viewModel.excludedCount > 0 {
                Button {
                    resetExclusions()
                } label: {
                    Text(L10n.CouchDecider.bringBack(viewModel.excludedCount))
                }
                .backport
                .buttonStyle(.glass)
            }
        }
        .focusSection()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Card

    /// The reel while it spins, otherwise the displayed card's poster. Flips, drops and scales.
    private var posterArea: some View {
        ZStack {
            if isReeling {
                CouchDeciderSlotReel(
                    items: reelItems,
                    landingItemID: viewModel.current?.id,
                    spinID: reelSpinID,
                    duration: reelDuration
                ) {
                    reelDidLand()
                }
            } else if let displayedItem {
                CouchDeciderView.CardPoster(item: displayedItem)
                    .id(displayedItem.id)
                    .transition(.opacity)
            }
        }
        .aspectRatio(2 / 3, contentMode: .fit)
        .rotation3DEffect(.degrees(flipAngle), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
        .rotationEffect(.degrees(cardTilt))
        .scaleEffect(cardScale)
        .offset(y: dropOffset)
        .opacity(cardOpacity)
        .shadow(color: .black.opacity(0.45), radius: UIDevice.isTV ? 30 : 18, y: UIDevice.isTV ? 16 : 10)
    }

    @ViewBuilder
    private var infoArea: some View {
        if let displayedCandidate {
            CouchDeciderView.CardInfo(
                candidate: displayedCandidate,
                item: displayedItem,
                isGroup: viewModel.couch.isGroup
            )
            .id(displayedCandidate.id)
            .transition(.opacity)
            .opacity(isInfoVisible && !isReeling ? 1 : 0)
        }
    }

    private var actionBar: some View {
        CouchDeciderView.ActionBar(
            isResolving: isResolving,
            focusedAction: $focusedAction,
            onNotTonight: notTonight,
            onShuffle: shuffle,
            onWatch: watch,
            onDetails: details,
            onVote: isTVVoteAvailable ? startVote : nil
        )
    }

    /// The iPhone shows its vote button in the header (`voteCapsule`).
    private var isTVVoteAvailable: Bool {
        #if os(tvOS)
        return Self.isVoteAvailable(viewModel)
        #else
        return false
        #endif
    }

    #if os(tvOS)
    /// Siri Remote: poster on the left, metadata and the action bar on the right.
    /// The card is not focusable.
    private var tvCardLayout: some View {
        HStack(alignment: .center, spacing: 80) {
            posterArea
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 40) {
                Spacer(minLength: 0)

                infoArea
                    .animation(.easeInOut(duration: 0.3), value: displayedID)
                    .animation(.easeInOut(duration: 0.3), value: isInfoVisible)

                actionBar

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .edgePadding(.horizontal)
        .padding(.bottom, 20)
    }
    #endif

    #if os(iOS)
    /// iPhone: the card (poster + info) in the middle, swipeable; the action bar at the bottom.
    private var phoneCardLayout: some View {
        VStack(spacing: 16) {
            VStack(spacing: 14) {
                posterArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay {
                        swipeTint
                    }

                infoArea
                    .animation(.easeInOut(duration: 0.3), value: displayedID)
                    .animation(.easeInOut(duration: 0.3), value: isInfoVisible)
            }
            .contentShape(Rectangle())
            .offset(x: dragOffset)
            .rotationEffect(.degrees(Double(dragOffset) / 25), anchor: .bottom)
            .gesture(swipeGesture)
            .edgePadding(.horizontal)

            actionBar
                .edgePadding(.horizontal)
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: swipeCount)
    }

    /// Red with a thumbs down when dragging left (Not tonight), accent with shuffle when dragging right.
    @ViewBuilder
    private var swipeTint: some View {
        let progress = min(abs(dragOffset) / 120, 1)

        if dragOffset != 0 {
            ZStack {
                RoundedRectangle(cornerRadius: CouchDeciderSlotReel.cornerRadius, style: .continuous)
                    .fill(dragOffset < 0 ? Color.red : accentColor)
                    .opacity(0.45 * progress)

                Image(systemName: dragOffset < 0 ? "hand.thumbsdown.fill" : "shuffle")
                    .font(.system(size: 56, weight: .bold))
                    .foregroundStyle(.white)
                    .opacity(progress)
                    .scaleEffect(0.6 + 0.4 * progress)
            }
            .aspectRatio(2 / 3, contentMode: .fit)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard viewModel.current != nil else { return }

                if !isDragging {
                    isDragging = true
                    skipToLanding()
                }

                dragOffset = value.translation.width
            }
            .onEnded { value in
                isDragging = false

                let width = value.translation.width

                if width < -120 {
                    flyOff(direction: -1)
                } else if width > 120 {
                    flyOff(direction: 1)
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        dragOffset = 0
                    }
                }
            }
    }

    /// The card flies off screen, then Not tonight (left) or Shuffle (right).
    private func flyOff(direction: CGFloat) {
        swipeCount &+= 1

        runAnimation {
            withAnimation(.easeIn(duration: 0.2)) {
                dragOffset = direction * 700
            }

            try await Task.sleep(for: .milliseconds(200))

            finishSwipe(direction: direction)
        }
    }

    /// Synchronous on purpose: in an async context `viewModel.shuffle()` would resolve to
    /// the generated `async` overload and need an `await`.
    private func finishSwipe(direction: CGFloat) {
        pendingAnimation = .appear

        if direction < 0 {
            viewModel.notTonight()
        } else {
            viewModel.shuffle()
        }
    }
    #endif

    // MARK: - Actions

    private func shuffle() {
        guard viewModel.current != nil else { return }

        skipToLanding()
        pendingAnimation = .flip
        viewModel.shuffle()
    }

    private func notTonight() {
        guard viewModel.current != nil else { return }

        skipToLanding()
        pendingAnimation = .drop
        viewModel.notTonight()
    }

    private func watch() {
        guard viewModel.current != nil else { return }

        skipToLanding()
        viewModel.watch()
    }

    /// "Let everyone vote" (#33): the vote screen covers the decider.
    private func startVote() {
        guard let route = Self.voteRoute(viewModel) else { return }

        skipToLanding()
        router.route(to: route)
    }

    private func details() {
        guard let currentID = viewModel.current?.id,
              let item = viewModel.item(for: currentID)
        else { return }

        skipToLanding()
        router.route(to: .item(item: item))
    }

    private func setFilters(_ filters: CouchDeciderFilters) {
        skipToLanding()
        pendingAnimation = .reel(duration: 0.6)
        viewModel.setFilters(filters)
    }

    private func resetExclusions() {
        skipToLanding()
        hideUndo()
        pendingAnimation = .reel(duration: 0.6)
        viewModel.resetExclusions()
    }

    /// Brings back the last "Not tonight" title as the current card.
    private func undoNotTonight() {
        guard viewModel.canUndoNotTonight else { return }

        skipToLanding()
        hideUndo()
        pendingAnimation = .reel(duration: 0.6)
        viewModel.undoNotTonight()
    }

    private func retry() {
        skipToLanding()
        pendingAnimation = .reel(duration: 1.6)
        viewModel.load()
    }

    /// Offers "Undo" in the filter row for about 5 seconds.
    private func offerUndo() {
        undoTask?.cancel()
        isUndoOffered = true

        undoTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(5))
            } catch {
                return
            }

            isUndoOffered = false
        }
    }

    private func hideUndo() {
        undoTask?.cancel()
        undoTask = nil
        isUndoOffered = false
    }

    /// The player covers the decider; closing it returns here on the same card.
    private func play(_ item: BaseItemDto) {
        guard let session = viewModel.userSession,
              let route = CouchDeciderPlayback.route(for: item, session: session)
        else { return }

        router.route(to: route)
    }

    private func focusWatchIfNeeded(for state: CouchDeciderViewModel._State) {
        #if os(tvOS)
        guard state == .content else { return }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))

            if focusedAction == nil {
                focusedAction = .watch
            }
        }
        #endif
    }

    // MARK: - Animation

    /// Plays the animation the last action asked for, landing on `viewModel.current`.
    private func cardDidChange() {
        let animation = pendingAnimation
        pendingAnimation = .crossfade

        if viewModel.didWrap {
            toastProxy.present(L10n.CouchDecider.startingOver, systemName: "arrow.counterclockwise")
        }

        guard let newID = viewModel.current?.id else {
            skipToLanding()
            return
        }

        if reduceMotion {
            crossfade(to: newID)
            return
        }

        switch animation {
        case let .reel(duration):
            startReel(duration: duration)
        case .flip:
            flip(to: newID)
        case .drop:
            drop(to: newID)
        case .appear:
            appear(to: newID)
        case .crossfade:
            crossfade(to: newID)
        }
    }

    /// Cancels any running animation and shows the current card at rest.
    private func skipToLanding() {
        animationTask?.cancel()
        animationTask = nil

        var transaction = Transaction()
        transaction.disablesAnimations = true

        withTransaction(transaction) {
            isReeling = false
            displayedID = viewModel.current?.id
            isInfoVisible = true
            resetCardTransforms()
        }
    }

    private func resetCardTransforms() {
        flipAngle = 0
        dropOffset = 0
        cardOpacity = 1
        cardScale = 1
        cardTilt = 0
        #if os(iOS)
        dragOffset = 0
        #endif
    }

    private func runAnimation(_ body: @escaping @MainActor () async throws -> Void) {
        animationTask?.cancel()
        animationTask = Task { @MainActor in
            do {
                try await body()
            } catch {
                // Cancelled: the next action already skipped to the landing.
            }
        }
    }

    private func crossfade(to newID: String) {
        animationTask?.cancel()
        animationTask = nil
        isReeling = false
        resetCardTransforms()

        withAnimation(.easeInOut(duration: 0.35)) {
            displayedID = newID
            isInfoVisible = true
        }
    }

    // MARK: Reel

    private func startReel(duration: TimeInterval) {
        animationTask?.cancel()
        animationTask = nil
        resetCardTransforms()

        reelItems = makeReelItems()
        reelDuration = duration
        isInfoVisible = false
        isReeling = true
        reelSpinID &+= 1
    }

    /// Up to 12 deck cards, padded with other candidates so short decks still spin.
    private func makeReelItems() -> [BaseItemDto] {
        var ids = viewModel.upcomingCandidates(12).map(\.id)

        if ids.count < 8 {
            for candidate in viewModel.pool.candidates.shuffled() where !ids.contains(candidate.id) {
                ids.append(candidate.id)

                if ids.count >= 12 {
                    break
                }
            }
        }

        return ids.compactMap { viewModel.item(for: $0) }
    }

    private func reelDidLand() {
        guard isReeling else { return }

        var transaction = Transaction()
        transaction.disablesAnimations = true

        withTransaction(transaction) {
            isReeling = false
            displayedID = viewModel.current?.id
        }

        withAnimation(.easeOut(duration: 0.35)) {
            isInfoVisible = true
        }
    }

    // MARK: Flip, Drop, Appear

    /// 3D card flip on the y axis: 0→90°, swap the content, -90→0. About 0.45 s.
    private func flip(to newID: String) {
        runAnimation {
            withAnimation(.easeIn(duration: 0.2)) {
                flipAngle = 90
            }

            try await Task.sleep(for: .milliseconds(200))

            swapWithoutAnimation(to: newID) {
                flipAngle = -90
            }

            try await Task.sleep(for: .milliseconds(16))

            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                flipAngle = 0
            }
        }
    }

    /// The card drops and fades, then the next one flips in.
    private func drop(to newID: String) {
        runAnimation {
            withAnimation(.easeIn(duration: 0.22)) {
                dropOffset = UIDevice.isTV ? 160 : 100
                cardTilt = -6
                cardOpacity = 0
            }

            try await Task.sleep(for: .milliseconds(220))

            swapWithoutAnimation(to: newID) {
                dropOffset = 0
                cardTilt = 0
                cardOpacity = 1
                flipAngle = -90
            }

            try await Task.sleep(for: .milliseconds(16))

            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                flipAngle = 0
            }
        }
    }

    /// After a swipe flew the old card off screen: the next one scales in.
    private func appear(to newID: String) {
        runAnimation {
            swapWithoutAnimation(to: newID) {
                resetCardTransforms()
                cardScale = 0.85
                cardOpacity = 0
            }

            try await Task.sleep(for: .milliseconds(16))

            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                cardScale = 1
                cardOpacity = 1
            }
        }
    }

    private func swapWithoutAnimation(to newID: String, _ changes: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true

        withTransaction(transaction) {
            isReeling = false
            displayedID = newID
            isInfoVisible = true
            changes()
        }
    }
}
