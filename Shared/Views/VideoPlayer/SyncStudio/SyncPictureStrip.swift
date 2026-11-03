//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

/// The film's timeline as a ruler that moves under a fixed centre line: the frame on screen.
///
/// It reads like the waveform strip below it. There is no thumb, so it can travel the whole
/// film at a pace that still finds the right second.
struct SyncPictureStrip: View {

    /// Seconds of film across the strip.
    static let visibleSeconds: Double = 30

    let seconds: Double
    let isFocused: Bool
    let isEditing: Bool

    private var cornerRadius: CGFloat {
        UIDevice.isTV ? 18 : 10
    }

    private static func label(for seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = seconds % 3600 / 60
        let remainder = seconds % 60

        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainder)
            : String(format: "%d:%02d", minutes, remainder)
    }

    private func drawRuler(in context: GraphicsContext, size: CGSize) {
        guard size.width > 0 else { return }

        let pointsPerSecond = size.width / Self.visibleSeconds
        let first = Int((seconds - Self.visibleSeconds / 2).rounded(.down))
        let last = Int((seconds + Self.visibleSeconds / 2).rounded(.up))
        let rulerHeight = size.height * 0.4
        var minorTicks = Path()
        var majorTicks = Path()

        for second in max(0, first) ... max(0, last) {
            let x = size.width / 2 + (Double(second) - seconds) * pointsPerSecond
            let isMajor = second % 5 == 0
            let tickHeight = isMajor ? rulerHeight : rulerHeight * 0.5

            if isMajor {
                majorTicks.addRect(CGRect(x: x - 0.75, y: 0, width: 1.5, height: tickHeight))
                context.draw(
                    Text(Self.label(for: second))
                        .font(UIDevice.isTV ? .caption2 : .system(size: 10))
                        .monospacedDigit()
                        .foregroundStyle(Color.Couchfin.mist),
                    at: CGPoint(x: x, y: tickHeight + 2),
                    anchor: .top
                )
            } else {
                minorTicks.addRect(CGRect(x: x - 0.5, y: 0, width: 1, height: tickHeight))
            }
        }

        context.fill(minorTicks, with: .color(Color.Couchfin.mist.opacity(0.5)))
        context.fill(majorTicks, with: .color(Color.Couchfin.mist))
    }

    private func drawPlayhead(in context: GraphicsContext, size: CGSize) {
        let lineWidth: CGFloat = UIDevice.isTV ? 3 : 2

        context.fill(
            Path(CGRect(x: size.width / 2 - lineWidth / 2, y: 0, width: lineWidth, height: size.height)),
            with: .color(.white)
        )
    }

    var body: some View {
        Canvas { context, size in
            drawRuler(in: context, size: size)
            drawPlayhead(in: context, size: size)
        }
        .background {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.Couchfin.trench.opacity(isFocused || isEditing ? 0.85 : 0.6))
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(isFocused ? Color.Couchfin.glint : Color.Couchfin.hairline, lineWidth: isFocused ? 3 : 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .animation(.easeInOut(duration: 0.2), value: isFocused)
    }
}

#if os(tvOS)
/// Swipes on the remote travel through the film, one second per slider unit.
struct SyncPictureSliderStyle: SliderContainerStyle {

    func makeBody(configuration: SliderContainerStyleConfiguration) -> some View {
        SyncPictureStrip(
            seconds: configuration.value,
            isFocused: configuration.isFocused,
            isEditing: configuration.isEditing
        )
    }
}
#endif
