//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

/// A slot-machine reel of portrait posters.
///
/// Posters cycle vertically inside the reel's frame. The steps start fast (~60 ms) and ease
/// out to ~350 ms over `duration`, then the reel lands on `landingItemID` with a spring
/// overshoot and calls `onLanded` once.
///
/// - A new `spinID` starts a new spin. The spin is a `Task` cancelled on disappear.
/// - `landingItemID == nil` spins at a steady pace forever (a loading state). With no
///   `items` it spins placeholder cards.
/// - Reduce Motion: no spin, the landing item crossfades in.
///
/// Size it from outside; it keeps a 2:3 portrait ratio.
struct CouchDeciderSlotReel: View {

    /// The corner radius of the reel, and of the decider's card.
    static var cornerRadius: CGFloat {
        #if os(tvOS)
        24
        #else
        16
        #endif
    }

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    @State
    private var displayedItem: BaseItemDto?
    /// Bumped on every step, so each poster is a new view that slides in.
    @State
    private var frameID: Int = 0
    @State
    private var blurRadius: CGFloat = 0
    @State
    private var tickCount: Int = 0
    @State
    private var landCount: Int = 0
    @State
    private var landedSpinID: Int?

    private let duration: TimeInterval
    private let items: [BaseItemDto]
    private let landingItemID: String?
    private let onLanded: () -> Void
    private let spinID: Int

    /// Spins through `items` and lands on `landingItemID`; calls `onLanded` once. Reduce Motion → no spin.
    ///
    /// - Parameter duration: How long the spin takes before landing. About 1.6 s on open, 0.6 s for a mini-reel.
    init(
        items: [BaseItemDto],
        landingItemID: String?,
        spinID: Int,
        duration: TimeInterval = 1.6,
        onLanded: @escaping () -> Void = {}
    ) {
        self.duration = duration
        self.items = items
        self.landingItemID = landingItemID
        self.onLanded = onLanded
        self.spinID = spinID

        let firstOther = items.first { $0.id != landingItemID }
        let landing = items.first { $0.id != nil && $0.id == landingItemID }
        _displayedItem = State(initialValue: firstOther ?? landing)
    }

    private var landingItem: BaseItemDto? {
        guard let landingItemID else { return nil }

        return items.first { $0.id == landingItemID }
    }

    private var reelItems: [BaseItemDto] {
        items.filter { $0.id != landingItemID }
    }

    /// Slot machine: the next poster drops in from the top. Reduce Motion: a crossfade.
    private var frameTransition: AnyTransition {
        if reduceMotion {
            return AnyTransition.opacity
        }

        return AnyTransition.asymmetric(
            insertion: AnyTransition.move(edge: .top),
            removal: AnyTransition.move(edge: .bottom)
        )
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.complexSecondary)

            frameView
                .id(frameID)
                .transition(frameTransition)
        }
        .aspectRatio(2 / 3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(displayedItem?.displayTitle ?? "")
        .task(id: spinID) {
            await spin()
        }
        #if os(iOS)
        .sensoryFeedback(.selection, trigger: tickCount)
        .sensoryFeedback(.success, trigger: landCount)
        #endif
    }

    @ViewBuilder
    private var frameView: some View {
        if let displayedItem {
            PosterImage(item: displayedItem, type: .portrait, size: .medium)
                .blur(radius: blurRadius)
        } else {
            SystemImageContentView(systemName: "film")
                .background(.complexSecondary)
        }
    }

    // MARK: - Spin

    private func show(_ item: BaseItemDto?, animation: Animation?) {
        withAnimation(animation) {
            displayedItem = item
            frameID &+= 1
        }
    }

    private func land() {
        guard landedSpinID != spinID else { return }

        landedSpinID = spinID
        landCount &+= 1
        onLanded()
    }

    private func spin() async {
        let others = reelItems

        // Reduce Motion, or nothing to spin through: crossfade to the landing.
        if reduceMotion || (landingItemID != nil && others.isEmpty) {
            if let landingItem, landingItem.id != displayedItem?.id {
                show(landingItem, animation: .easeInOut(duration: 0.3))
            }

            blurRadius = 0

            if landingItemID != nil {
                land()
            }
            return
        }

        guard let landingItem else {
            await idleSpin(through: others)
            return
        }

        var elapsed: TimeInterval = 0
        var index = 0

        while elapsed < duration {
            let progress = elapsed / max(duration, 0.01)
            let interval = 0.06 + 0.29 * progress * progress

            #if os(iOS)
            blurRadius = CGFloat(3 * (1 - progress))
            #endif

            show(others[index % others.count], animation: .linear(duration: interval * 0.85))
            tickCount &+= 1
            index += 1

            do {
                try await Task.sleep(for: .seconds(interval))
            } catch {
                return
            }

            elapsed += interval
        }

        guard !Task.isCancelled else { return }

        blurRadius = 0
        show(landingItem, animation: .spring(response: 0.42, dampingFraction: 0.58))
        land()
    }

    /// The loading state: a steady spin until the view goes away or a landing arrives.
    private func idleSpin(through others: [BaseItemDto]) async {
        var index = 0

        while !Task.isCancelled {
            let next: BaseItemDto? = others.isEmpty ? nil : others[index % others.count]

            show(next, animation: .linear(duration: 0.14))
            index += 1

            do {
                try await Task.sleep(for: .milliseconds(170))
            } catch {
                return
            }
        }
    }
}
