//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

/// Couchfin's dark water: the abyss, with a little light coming in from the edges.
struct AbyssBackground: View {

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.Couchfin.deep, Color.Couchfin.abyss],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.55)
            )

            // fin blue spilling in from the top trailing corner
            RadialGradient(
                colors: [Color.Couchfin.fin.opacity(0.26), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 520
            )

            // a hint of bloom from the bottom leading corner
            RadialGradient(
                colors: [Color.Couchfin.orchid.opacity(0.10), .clear],
                center: .bottomLeading,
                startRadius: 0,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
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

    /// Couchfin's raised surface for list and form rows.
    func couchfinRowBackground() -> some View {
        listRowBackground(Color.Couchfin.trench.opacity(0.55))
    }
}
