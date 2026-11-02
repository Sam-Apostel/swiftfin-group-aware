//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

/// Draws the sound around the paused frame as a waveform strip.
///
/// The centre line is the picture: the frame on screen. The ruler is fixed to it and reads how far
/// a sound is from the picture. Sliding (the slider's value) moves the sound under the line.
struct SyncWaveformSliderStyle: SliderContainerStyle {

    let envelope: AVSyncWaveform.Envelope?
    let videoSeconds: Double
    let offsetRange: ClosedRange<Double>
    let visibleSeconds: Double

    func makeBody(configuration: SliderContainerStyleConfiguration) -> some View {
        SyncWaveformStrip(
            envelope: envelope,
            videoSeconds: videoSeconds,
            offsetMilliseconds: offsetRange.lowerBound + configuration.progress * (offsetRange.upperBound - offsetRange.lowerBound),
            visibleSeconds: visibleSeconds,
            isFocused: configuration.isFocused,
            isEditing: configuration.isEditing
        )
    }
}

private struct SyncWaveformStrip: View {

    let envelope: AVSyncWaveform.Envelope?
    let videoSeconds: Double
    let offsetMilliseconds: Double
    let visibleSeconds: Double
    let isFocused: Bool
    let isEditing: Bool

    private var rulerHeight: CGFloat {
        UIDevice.isTV ? 34 : 18
    }

    /// Ruler labels every second on iPhone and iPad, every half second on TV.
    private var labelStepMilliseconds: Int {
        UIDevice.isTV ? 500 : 1000
    }

    private var cornerRadius: CGFloat {
        UIDevice.isTV ? 18 : 10
    }

    private func rulerLabel(_ milliseconds: Int) -> String {
        if milliseconds == 0 {
            return L10n.AVSync.milliseconds(0)
        }

        return milliseconds > 0 ? "+\(milliseconds)" : "−\(-milliseconds)"
    }

    private func drawWaveform(in context: GraphicsContext, size: CGSize) {
        guard let envelope, envelope.bucketSeconds > 0, size.width > 0 else { return }

        // The sound heard with this offset at the frame: a positive offset plays it later
        let centerSeconds = videoSeconds - offsetMilliseconds / 1000
        let pointsPerSecond = size.width / visibleSeconds
        let firstSeconds = centerSeconds - visibleSeconds / 2
        let lastSeconds = centerSeconds + visibleSeconds / 2

        let firstIndex = max(0, Int(((firstSeconds - envelope.startSeconds) / envelope.bucketSeconds).rounded(.down)))
        let lastIndex = min(envelope.levels.count - 1, Int(((lastSeconds - envelope.startSeconds) / envelope.bucketSeconds).rounded(.up)))

        guard firstIndex <= lastIndex else { return }

        let midY = size.height / 2
        let maximumHalfHeight = max(1, midY - 2)
        let barWidth = max(1, envelope.bucketSeconds * pointsPerSecond)
        var path = Path()

        for index in firstIndex ... lastIndex {
            let seconds = envelope.startSeconds + Double(index) * envelope.bucketSeconds
            let x = size.width / 2 + (seconds - centerSeconds) * pointsPerSecond
            let halfHeight = max(0.5, CGFloat(envelope.levels[index]) * maximumHalfHeight)

            path.addRect(CGRect(x: x, y: midY - halfHeight, width: barWidth, height: halfHeight * 2))
        }

        context.fill(path, with: .color(Color.Couchfin.glint.opacity(0.9)))
    }

    private func drawRuler(in context: GraphicsContext, size: CGSize) {
        let pointsPerMillisecond = size.width / (visibleSeconds * 1000)
        let halfSpan = Int(visibleSeconds * 500)
        var minorTicks = Path()
        var majorTicks = Path()

        for milliseconds in stride(from: -halfSpan, through: halfSpan, by: 100) {
            let x = size.width / 2 + CGFloat(milliseconds) * pointsPerMillisecond
            let isMajor = milliseconds % labelStepMilliseconds == 0
            let tickHeight: CGFloat = isMajor ? rulerHeight * 0.4 : rulerHeight * 0.2

            if isMajor {
                majorTicks.addRect(CGRect(x: x - 0.75, y: 0, width: 1.5, height: tickHeight))
                context.draw(
                    Text(rulerLabel(milliseconds))
                        .font(UIDevice.isTV ? .caption2 : .system(size: 9))
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
        let markerSize: CGFloat = UIDevice.isTV ? 14 : 8
        let midX = size.width / 2

        context.fill(
            Path(CGRect(x: midX - lineWidth / 2, y: 0, width: lineWidth, height: size.height)),
            with: .color(.white)
        )

        var marker = Path()
        marker.move(to: CGPoint(x: midX - markerSize / 2, y: 0))
        marker.addLine(to: CGPoint(x: midX + markerSize / 2, y: 0))
        marker.addLine(to: CGPoint(x: midX, y: markerSize * 0.8))
        marker.closeSubpath()
        context.fill(marker, with: .color(.white))
    }

    var body: some View {
        VStack(spacing: 0) {
            Canvas { context, size in
                drawWaveform(in: context, size: size)
                drawPlayhead(in: context, size: size)
            }

            Canvas { context, size in
                drawRuler(in: context, size: size)
            }
            .frame(height: rulerHeight)
        }
        .padding(.top, UIDevice.isTV ? 8 : 4)
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
