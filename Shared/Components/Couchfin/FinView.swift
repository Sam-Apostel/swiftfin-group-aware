//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

/// The glowing fin from the app icon, drawn live so it stays sharp at any size.
///
/// Use it the way the brand guide says: swimming off an edge, one per screen,
/// never on top of artwork or video. Pass `glow: false` for small sizes.
struct FinView: View {

    enum Heading {
        /// Head on the leading side, swimming towards the leading edge.
        case leading
        /// Head on the trailing side.
        case trailing
    }

    var heading: Heading = .leading
    var glow: Bool = true

    var body: some View {
        GeometryReader { proxy in
            let rimWidth = max(1, proxy.size.width / 160)

            ZStack {
                if glow {
                    FinShape()
                        .stroke(Color.Couchfin.rim, lineWidth: rimWidth * 5)
                        .blur(radius: rimWidth * 3)
                        .opacity(0.85)
                }

                FinShape()
                    .fill(Color.Couchfin.body)

                // darker core, so the light stays on the edge
                FinShape()
                    .fill(
                        RadialGradient(
                            colors: [Color(hex: "#000530").opacity(0.75), .clear],
                            center: UnitPoint(x: 0.42, y: 0.5),
                            startRadius: 0,
                            endRadius: proxy.size.width * 0.42
                        )
                    )

                FinShape()
                    .stroke(Color.Couchfin.rim, lineWidth: rimWidth)
            }
            .scaleEffect(x: heading == .trailing ? -1 : 1, y: 1)
        }
        .aspectRatio(FinShape.aspectRatio, contentMode: .fit)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

/// A fin gently swimming in place: Couchfin's loading indicator.
struct SwimmingFin: View {

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    var width: CGFloat = 56

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let phase = sin(t * 2.4)

            FinView(glow: width >= 40)
                .frame(width: width)
                // the tail flicks more than the head
                .rotation3DEffect(.degrees(phase * 18), axis: (x: 0, y: 1, z: 0), anchor: .leading)
                .rotationEffect(.degrees(phase * 3))
                .offset(y: CGFloat(sin(t * 1.2)) * width * 0.04)
        }
        .frame(width: width, height: width / FinShape.aspectRatio * 1.3)
        .accessibilityElement()
        .accessibilityLabel(Text(L10n.Couchfin.loading))
    }
}
