//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

/// The Couchfin fin, straight from the brand artwork: textured body, glowing rim.
///
/// Use it the way the brand guide says: one per screen, entering from an edge,
/// never on top of artwork or video.
struct FinView: View {

    enum Variant {
        /// The whole fish: round head on the leading side, forked tail on the trailing side.
        case fish
        /// Only the tail, for swimming off an edge.
        case tail

        var resource: ImageResource {
            switch self {
            case .fish:
                .couchfinFin
            case .tail:
                .couchfinTail
            }
        }
    }

    enum Heading {
        /// Head on the leading side (as drawn).
        case leading
        /// Mirrored: head on the trailing side.
        case trailing
    }

    var variant: Variant = .fish
    var heading: Heading = .leading

    var body: some View {
        Image(variant.resource)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .scaleEffect(x: heading == .trailing ? -1 : 1, y: 1)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

/// The fin gently swimming in place: Couchfin's loading indicator.
struct SwimmingFin: View {

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    var width: CGFloat = UIDevice.isTV ? 160 : 84

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let phase = sin(t * 2.4)

            FinView()
                .frame(width: width)
                // the tail flicks more than the head
                .rotation3DEffect(.degrees(phase * 14), axis: (x: 0, y: 1, z: 0), anchor: .leading)
                .rotationEffect(.degrees(phase * 2.5))
                .offset(y: CGFloat(sin(t * 1.2)) * width * 0.04)
        }
        .frame(width: width * 1.1, height: width * 0.75)
        .accessibilityElement()
        .accessibilityLabel(Text(L10n.Couchfin.loading))
    }
}
