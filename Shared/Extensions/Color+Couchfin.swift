//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

// MARK: - Couchfin palette

/// The Couchfin palette: the UI is dark water and the content is the light.
///
/// Light only ever comes from an edge, like the rim of the fin in the app icon:
/// cyan where it's lit, bloom (magenta) at the tail.
extension Color {

    enum Couchfin {

        /// Every background.
        static let abyss = Color(hex: "#01061A")
        /// A step up from the abyss: sheets, the top of a gradient.
        static let deep = Color(hex: "#020D33")
        /// Cards, list groups and other raised surfaces.
        static let trench = Color(hex: "#071552")

        /// The fin's body blue.
        static let fin = Color(hex: "#1238FF")
        /// The app tint: a lighter fin blue that reads as text on the abyss.
        static let accent = Color(hex: "#4C7DFF")
        /// The bright cyan of the lit edge.
        static let bio = Color(hex: "#00B9FB")
        /// The brightest point of the rim: focus, live, now.
        static let glint = Color(hex: "#3FEDFD")
        static let violet = Color(hex: "#7A5CFF")
        /// The tail's magenta: the couch, watching together.
        static let bloom = Color(hex: "#F949FA")
        static let orchid = Color(hex: "#C026F5")

        /// Secondary text on the abyss.
        static let mist = Color(hex: "#9FB0D9")
        /// Hairlines and borders on raised surfaces.
        static let hairline = Color(hex: "#7896FF").opacity(0.16)

        /// The rim, from the lit edge to the tail.
        static let rimColors: [Color] = [bio, glint, violet, bloom]

        static var rim: LinearGradient {
            LinearGradient(colors: rimColors, startPoint: .leading, endPoint: .trailing)
        }

        /// The fin body, from the head to the tail tip.
        static var body: LinearGradient {
            LinearGradient(
                stops: [
                    .init(color: Color(hex: "#0D2FE0"), location: 0),
                    .init(color: Color(hex: "#061AA8"), location: 0.35),
                    .init(color: Color(hex: "#04107E"), location: 0.62),
                    .init(color: Color(hex: "#3A1FD0"), location: 0.86),
                    .init(color: Color(hex: "#F04BFA"), location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }

        /// The "watch together" button fill.
        static var together: LinearGradient {
            LinearGradient(
                stops: [
                    .init(color: fin, location: 0),
                    .init(color: Color(hex: "#5B2BFF"), location: 0.7),
                    .init(color: orchid, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }
}
