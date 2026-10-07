//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

/// The Couchfin fin: a rounded head, a narrow waist and a forked tail, head on the leading side.
///
/// Drawn in a 100 × 46 design box and scaled to fit the rect (aspect ratio is not preserved,
/// so frame it with `FinShape.aspectRatio`).
struct FinShape: Shape {

    /// Width / height of the design box.
    static let aspectRatio: CGFloat = 100 / 46

    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 100
        let sy = rect.height / 46

        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy)
        }

        var path = Path()

        path.move(to: p(0, 23))
        // top of the head and the back, into the waist
        path.addCurve(to: p(19.5, 4.6), control1: p(0, 10.5), control2: p(8.5, 4.6))
        path.addCurve(to: p(55, 15.8), control1: p(31, 4.6), control2: p(43, 11))
        path.addCurve(to: p(74, 13.4), control1: p(61, 18.2), control2: p(67, 17.6))
        // upper lobe of the tail
        path.addCurve(to: p(97, 0.5), control1: p(82, 8.6), control2: p(90, 2.2))
        path.addCurve(to: p(100.2, 3.2), control1: p(100.4, -0.3), control2: p(101.2, 1.6))
        path.addLine(to: p(88.6, 20.2))
        // the fork
        path.addCurve(to: p(88.6, 25.8), control1: p(87.4, 22), control2: p(87.4, 24))
        path.addLine(to: p(100.2, 42.8))
        // lower lobe of the tail
        path.addCurve(to: p(97, 45.5), control1: p(101.2, 44.4), control2: p(100.4, 46.3))
        path.addCurve(to: p(74, 32.6), control1: p(90, 43.8), control2: p(82, 37.4))
        path.addCurve(to: p(55, 30.2), control1: p(67, 28.4), control2: p(61, 27.8))
        // the belly, back to the head
        path.addCurve(to: p(19.5, 41.4), control1: p(43, 35), control2: p(31, 41.4))
        path.addCurve(to: p(0, 23), control1: p(8.5, 41.4), control2: p(0, 35.5))
        path.closeSubpath()

        return path
    }
}
