//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

/// How a universe looks: the server picks a preset, Couchfin draws it. Colours come from the
/// universe's own artwork when it loads; until then the preset's colour stands in.
struct UniverseStyle: Equatable {

    let preset: String
    let typeface: String
    let texture: String
    let presetColor: Color
    /// Off when the person turned themed timelines off: Couchfin's own look.
    let isThemed: Bool

    init(theme: UniverseTheme, isThemed: Bool = true) {
        self.preset = theme.preset
        self.typeface = theme.typeface
        self.texture = isThemed ? theme.texture : "none"
        self.isThemed = isThemed
        self.presetColor = theme.accent.flatMap(Color.init(universeHex:)) ?? Self.color(for: theme.preset)
    }

    static func color(for preset: String) -> Color {
        switch preset {
        case "cosmic": Color(red: 0.36, green: 0.42, blue: 0.95)
        case "heroic": Color(red: 0.86, green: 0.18, blue: 0.2)
        case "mythic": Color(red: 0.78, green: 0.58, blue: 0.27)
        case "gothic": Color(red: 0.45, green: 0.3, blue: 0.55)
        case "ink": Color(red: 0.2, green: 0.62, blue: 0.62)
        case "blocky": Color(red: 0.36, green: 0.7, blue: 0.3)
        case "playful": Color(red: 0.98, green: 0.58, blue: 0.22)
        case "deep-time": Color(red: 0.8, green: 0.64, blue: 0.42)
        case "backlog": Color(red: 0.55, green: 0.55, blue: 0.6)
        default: Color(red: 0.62, green: 0.52, blue: 1)
        }
    }

    // MARK: - Type

    private var design: Font.Design {
        guard isThemed else { return .default }

        switch typeface {
        case "serif": return .serif
        case "mono": return .monospaced
        case "rounded": return .rounded
        default: return .default
        }
    }

    private var width: Font.Width? {
        guard isThemed else { return nil }

        switch typeface {
        case "condensed": return .condensed
        case "futuristic": return .expanded
        default: return nil
        }
    }

    func font(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        let font = Font.system(style, design: design, weight: weight)
        return width.map { font.width($0) } ?? font
    }

    /// Small caps-like labels: eras, kinds, years.
    func label(_ style: Font.TextStyle = .caption) -> Font {
        let font = Font.system(style, design: design == .serif ? .serif : .monospaced, weight: .semibold)
        return width.map { font.width($0) } ?? font
    }
}

extension Color {

    /// "#RRGGBB" or "RRGGBB".
    init?(universeHex: String) {
        let hex = universeHex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }

        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

// MARK: - Background

/// The universe's backdrop: its colour fading into black, with the preset's texture on top.
struct UniverseBackground: View {

    let style: UniverseStyle
    let color: Color
    let seed: String

    var body: some View {
        ZStack {
            Color.black

            LinearGradient(
                colors: [color.opacity(0.55), color.opacity(0.18), .black],
                startPoint: .top,
                endPoint: .bottom
            )

            UniverseTexture(kind: style.texture, color: color, seed: seed)
                .opacity(0.9)
                .blendMode(.plusLighter)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Procedural textures, drawn once per size. Deterministic per universe, so they don't shimmer.
struct UniverseTexture: View {

    let kind: String
    let color: Color
    let seed: String

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            var random = SeededRandom(seed: seed)
            switch kind {
            case "grain":
                drawGrain(&context, size, &random, density: 0.0016, alpha: 0.07)
            case "starfield":
                drawStars(&context, size, &random)
            case "halftone":
                drawHalftone(&context, size)
            case "parchment":
                drawWash(&context, size, &random, blobs: 7, alpha: 0.07, tint: Color(red: 1, green: 0.85, blue: 0.6))
                drawGrain(&context, size, &random, density: 0.0012, alpha: 0.06)
            case "ink":
                drawWash(&context, size, &random, blobs: 9, alpha: 0.1, tint: color)
            case "pixel":
                drawPixels(&context, size, &random)
            case "paper":
                drawLines(&context, size, spacing: 28, alpha: 0.05)
            case "strata":
                drawStrata(&context, size, &random)
            default:
                break
            }
        }
        .allowsHitTesting(false)
    }

    private func drawGrain(_ context: inout GraphicsContext, _ size: CGSize, _ random: inout SeededRandom, density: Double, alpha: Double) {
        let count = Int(size.width * size.height * density)
        for _ in 0 ..< count {
            let rect = CGRect(x: random.next() * size.width, y: random.next() * size.height, width: 1.2, height: 1.2)
            context.fill(Path(rect), with: .color(.white.opacity(alpha * (0.4 + random.next()))))
        }
    }

    private func drawStars(_ context: inout GraphicsContext, _ size: CGSize, _ random: inout SeededRandom) {
        let count = Int(size.width * size.height / 2600)
        for _ in 0 ..< count {
            let radius = 0.4 + random.next() * random.next() * 1.8
            let rect = CGRect(x: random.next() * size.width, y: random.next() * size.height, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.15 + random.next() * 0.55)))
        }
    }

    private func drawHalftone(_ context: inout GraphicsContext, _ size: CGSize) {
        let spacing: CGFloat = 14
        var y: CGFloat = 0
        while y < size.height {
            let fade = 1 - y / max(size.height, 1)
            var x: CGFloat = (Int(y / spacing) % 2 == 0) ? 0 : spacing / 2
            while x < size.width {
                let radius = 0.6 + 2.6 * fade * fade
                context.fill(
                    Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                    with: .color(.white.opacity(0.06))
                )
                x += spacing
            }
            y += spacing
        }
    }

    private func drawWash(_ context: inout GraphicsContext, _ size: CGSize, _ random: inout SeededRandom, blobs: Int, alpha: Double, tint: Color) {
        context.addFilter(.blur(radius: 60))
        for _ in 0 ..< blobs {
            let radius = (0.15 + random.next() * 0.3) * max(size.width, size.height)
            let center = CGPoint(x: random.next() * size.width, y: random.next() * size.height)
            context.fill(
                Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                with: .color(tint.opacity(alpha * (0.5 + random.next())))
            )
        }
    }

    private func drawPixels(_ context: inout GraphicsContext, _ size: CGSize, _ random: inout SeededRandom) {
        let cell: CGFloat = 22
        var y: CGFloat = 0
        while y < size.height {
            var x: CGFloat = 0
            while x < size.width {
                let value = random.next()
                if value > 0.55 {
                    context.fill(
                        Path(CGRect(x: x, y: y, width: cell - 2, height: cell - 2)),
                        with: .color(.white.opacity((value - 0.55) * 0.12))
                    )
                }
                x += cell
            }
            y += cell
        }
    }

    private func drawLines(_ context: inout GraphicsContext, _ size: CGSize, spacing: CGFloat, alpha: Double) {
        var y: CGFloat = spacing
        while y < size.height {
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(path, with: .color(.white.opacity(alpha)), lineWidth: 1)
            y += spacing
        }
    }

    private func drawStrata(_ context: inout GraphicsContext, _ size: CGSize, _ random: inout SeededRandom) {
        var y: CGFloat = 0
        while y < size.height {
            let height = 18 + random.next() * 70
            context.fill(
                Path(CGRect(x: 0, y: y, width: size.width, height: height)),
                with: .color(.white.opacity(random.next() * 0.05))
            )
            y += height
        }
    }
}

/// SplitMix64: tiny, fast and the same on every device.
struct SeededRandom {

    private var state: UInt64

    init(seed: String) {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        self.state = hash
    }

    /// 0 ..< 1
    mutating func next() -> Double {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        return Double(value >> 11) / Double(1 << 53)
    }
}
