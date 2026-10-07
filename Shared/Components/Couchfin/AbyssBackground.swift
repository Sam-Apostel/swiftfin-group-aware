//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

/// Couchfin's dark water: the moody, cloudy volume from the app icon, drifting very slowly.
struct AbyssBackground: View {

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    @State
    private var isDrifting = false

    var body: some View {
        GeometryReader { proxy in
            let isPortrait = proxy.size.height > proxy.size.width

            Image(isPortrait ? .couchfinAbyssPortrait : .couchfinAbyssLandscape)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: proxy.size.width, height: proxy.size.height)
                // a slow drift, so the water feels alive without drawing attention
                .scaleEffect(isDrifting ? 1.12 : 1.04)
                .offset(x: isDrifting ? proxy.size.width * 0.02 : -proxy.size.width * 0.02)
                .clipped()
        }
        .background(Color.Couchfin.abyss)
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { return }

            withAnimation(.easeInOut(duration: 40).repeatForever(autoreverses: true)) {
                isDrifting = true
            }
        }
    }
}

extension View {

    /// Puts a screen in Couchfin's dark water: hides the system list/form backgrounds
    /// so the abyss shows through.
    func couchfinBackground() -> some View {
        #if os(iOS)
        scrollContentBackground(.hidden)
            .background {
                AbyssBackground()
            }
        #else
        background {
            AbyssBackground()
        }
        #endif
    }

    /// The background of a pushed screen. On tvOS the tab view already draws the deep
    /// (under the focused poster's backdrop), so pushed screens stay transparent there.
    @ViewBuilder
    func couchfinDestinationBackground() -> some View {
        #if os(iOS)
        couchfinBackground()
        #else
        self
        #endif
    }

    /// Couchfin's raised surface for list and form rows.
    func couchfinRowBackground() -> some View {
        listRowBackground(Color.Couchfin.trench.opacity(0.55))
    }
}
