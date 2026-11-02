//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

/// The sync studio, presented as a guest supplement: the paused picture stays visible above it.
struct SyncStudioSupplement: MediaPlayerSupplement {

    static let supplementID = "SyncStudio"

    static var waveformFocusID: String {
        "\(VideoPlayer.ViewState.Focus.supplementContent(supplementID)).waveform"
    }

    let model: SyncStudioModel

    var id: String {
        Self.supplementID
    }

    var displayTitle: String {
        L10n.AVSync.fixAudioSync
    }

    var preferredFocusID: String {
        Self.waveformFocusID
    }

    var videoPlayerBody: some PlatformView {
        SyncStudioView(model: model)
    }
}

// MARK: - View

private struct SyncStudioView: PlatformView {

    @Environment(\.safeAreaInsets)
    private var safeAreaInsets

    @Environment(VideoPlayer.ViewState.self)
    private var viewState

    @ObservedObject
    var model: SyncStudioModel

    private typealias Model = SyncStudioModel

    /// Slider units: 1 ms on touch (the sound follows the finger), 20 ms per unit on the
    /// Siri Remote, whose swipes move the value by one unit per 200 points.
    private var sliderUnit: Double {
        UIDevice.isTV ? 20 : 1
    }

    private var sliderTotal: Double {
        (Model.offsetRange.upperBound - Model.offsetRange.lowerBound) / sliderUnit
    }

    private var sliderValue: Binding<Double> {
        Binding(
            get: { (model.offsetMilliseconds - Model.offsetRange.lowerBound) / sliderUnit },
            set: { newValue in
                model.offsetMilliseconds = clamp(
                    newValue * sliderUnit + Model.offsetRange.lowerBound,
                    min: Model.offsetRange.lowerBound,
                    max: Model.offsetRange.upperBound
                )
            }
        )
    }

    private var spacing: CGFloat {
        UIDevice.isTV ? 20 : 8
    }

    private var waveformHeight: CGFloat {
        UIDevice.isTV ? 150 : 76
    }

    // MARK: - Header

    private var savedStatus: some View {
        HStack(spacing: UIDevice.isTV ? 16 : 8) {
            Label(
                model.correction?.hasDrift == true ? L10n.AVSync.savedWithDrift : L10n.AVSync.savedForFile,
                systemImage: "checkmark.icloud"
            )
            .foregroundStyle(Color.Couchfin.mist)
            .lineLimit(1)
            .minimumScaleFactor(0.75)

            Button(L10n.reset) {
                model.resetSaved()
            }
            .buttonStyle(.capsule)
            .controlSize(UIDevice.isTV ? .regular : .small)
        }
        .font(UIDevice.isTV ? .callout : .caption)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: spacing) {
            Text(L10n.AVSync.fixAudioSync)
                .font(UIDevice.isTV ? .title3.weight(.bold) : .subheadline.weight(.bold))
                .fontDesign(.rounded)
                .lineLimit(1)

            Spacer(minLength: 0)

            if model.correction != nil {
                savedStatus
            }
        }
        .syncStudioFocusSection()
    }

    // MARK: - Direction

    @ViewBuilder
    private var directionText: some View {
        switch model.direction {
        case .inSync:
            Text(L10n.AVSync.inSync)
                .fontWeight(.semibold)

            Text(L10n.AVSync.noShift)
                .foregroundStyle(Color.Couchfin.mist)

        case let .soundLate(milliseconds):
            Text(L10n.AVSync.soundLate(milliseconds))
                .fontWeight(.semibold)

            Image(systemName: "arrow.right")
                .foregroundStyle(Color.Couchfin.mist)

            Text(L10n.AVSync.playingEarlier(milliseconds))
                .foregroundStyle(Color.Couchfin.mist)

        case let .soundEarly(milliseconds):
            Text(L10n.AVSync.soundEarly(milliseconds))
                .fontWeight(.semibold)

            Image(systemName: "arrow.right")
                .foregroundStyle(Color.Couchfin.mist)

            Text(L10n.AVSync.playingLater(milliseconds))
                .foregroundStyle(Color.Couchfin.mist)
        }
    }

    private var directionRow: some View {
        HStack(spacing: UIDevice.isTV ? 16 : 8) {
            SyncDirectionDiagram(offsetMilliseconds: model.offsetMilliseconds)
                .frame(width: UIDevice.isTV ? 150 : 72, height: UIDevice.isTV ? 54 : 28)

            directionText
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 0)
        }
        .font(UIDevice.isTV ? .callout : .footnote)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Waveform

    private var envelope: AVSyncWaveform.Envelope? {
        if case let .loaded(envelope) = model.waveformState {
            return envelope
        }
        return nil
    }

    @ViewBuilder
    private var waveformMessage: some View {
        switch model.waveformState {
        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                Text(L10n.AVSync.listening)
            }

        case .failed:
            Text(L10n.AVSync.waveformFailed)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

        case .loaded:
            EmptyView()
        }
    }

    private var waveform: some View {
        SliderContainer(
            value: sliderValue,
            total: sliderTotal,
            isScrollingEnabled: !model.isPreviewing
        )
        .sliderContainerStyle(
            SyncWaveformSliderStyle(
                envelope: envelope,
                videoSeconds: model.videoSeconds,
                offsetRange: Model.offsetRange,
                visibleSeconds: Model.visibleSeconds
            )
        )
        .overlay {
            waveformMessage
                .font(UIDevice.isTV ? .callout : .caption)
                .foregroundStyle(Color.Couchfin.mist)
                .allowsHitTesting(false)
        }
        .frame(height: waveformHeight)
        .syncStudioFocus(SyncStudioSupplement.waveformFocusID)
        .accessibilityLabel(L10n.audioOffset)
        .accessibilityValue(Duration.milliseconds(Int64(model.offsetMilliseconds.rounded())).formatted(.playbackOffset))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: model.offsetMilliseconds = min(model.offsetMilliseconds + 10, Model.offsetRange.upperBound)
            case .decrement: model.offsetMilliseconds = max(model.offsetMilliseconds - 10, Model.offsetRange.lowerBound)
            @unknown default: break
            }
        }
    }

    // MARK: - Controls

    private var frameButtons: some View {
        Group {
            Button {
                model.stepFrame(forward: false)
            } label: {
                Label(L10n.AVSync.previousFrame, systemImage: "backward.frame")
                    .labelStyle(.iconOnly)
            }

            Button {
                model.stepFrame(forward: true)
            } label: {
                Label(L10n.AVSync.nextFrame, systemImage: "forward.frame")
                    .labelStyle(.iconOnly)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: UIDevice.isTV ? 24 : 8) {
            frameButtons

            Button {
                model.togglePreview()
            } label: {
                Label(
                    model.isPreviewing ? L10n.AVSync.stop : L10n.AVSync.check,
                    systemImage: model.isPreviewing ? "stop.fill" : "play.fill"
                )
            }

            Spacer(minLength: 0)

            Button {
                model.cancel()
            } label: {
                Label(L10n.cancel, systemImage: "xmark")
            }

            Button {
                model.save()
            } label: {
                Label(
                    model.addsSecondPoint ? L10n.AVSync.saveSecondPoint : L10n.AVSync.save,
                    systemImage: "checkmark"
                )
            }
        }
        .buttonStyle(.capsule)
        .controlSize(UIDevice.isTV ? .large : .small)
        .foregroundStyle(.white)
        .syncStudioFocusSection()
    }

    private var hint: String? {
        if model.addsSecondPoint {
            return L10n.AVSync.secondPointReady
        }

        if model.correction?.hasDrift == false {
            return L10n.AVSync.secondPointTooClose
        }

        return UIDevice.isTV ? L10n.AVSync.hintTV : L10n.AVSync.hintPhone
    }

    // MARK: - Body

    private var content: some View {
        VStack(alignment: .leading, spacing: spacing) {
            header

            directionRow

            waveform

            controls

            if let hint {
                Text(hint)
                    .font(UIDevice.isTV ? .caption : .caption2)
                    .foregroundStyle(Color.Couchfin.mist)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: UIDevice.isTV ? 1500 : 900)
        .frame(maxWidth: .infinity)
        .edgePadding(.horizontal)
        .padding(.vertical, UIDevice.isTV ? 12 : 6)
        .padding(.leading, safeAreaInsets.leading)
        .padding(.trailing, safeAreaInsets.trailing)
        .scrollIfLargerThanContainer()
        .padding(.bottom, safeAreaInsets.bottom)
    }

    var iOSView: some View {
        content
    }

    var tvOSView: some View {
        content
            .syncStudioFocusSection()
            .syncStudioFrameStepping(viewState: viewState, model: model)
    }
}

// MARK: - Platform helpers

private extension View {

    func syncStudioFocus(_ id: String) -> some View {
        #if os(tvOS)
        coordinatedFocus(id)
        #else
        self
        #endif
    }

    func syncStudioFocusSection() -> some View {
        #if os(tvOS)
        focusSection()
        #else
        self
        #endif
    }

    /// Clicking left or right on the remote steps the picture one frame. Swipes slide the sound.
    func syncStudioFrameStepping(viewState: VideoPlayer.ViewState, model: SyncStudioModel) -> some View {
        #if os(tvOS)
        onReceive(viewState.containerView?.onPressEvent ?? .init()) { press in
            guard press.phase == .ended,
                  press.type == .leftArrow || press.type == .rightArrow,
                  viewState.focusCoordinator.focusedIDs.contains(SyncStudioSupplement.waveformFocusID)
            else { return }

            model.stepFrame(forward: press.type == .rightArrow)
        }
        #else
        self
        #endif
    }
}

// MARK: - Diagram

/// A tiny picture-and-sound timeline: the sound mark sits right of the picture mark when the sound
/// is late, left of it when it's early, and the arrow shows which way it is being moved.
private struct SyncDirectionDiagram: View {

    let offsetMilliseconds: Double

    var body: some View {
        HStack(spacing: UIDevice.isTV ? 10 : 4) {
            VStack(spacing: UIDevice.isTV ? 10 : 4) {
                Image(systemName: "film")
                    .accessibilityLabel(L10n.AVSync.picture)
                Image(systemName: "waveform")
                    .accessibilityLabel(L10n.AVSync.sound)
            }
            .font(UIDevice.isTV ? .caption : .system(size: 9))
            .foregroundStyle(Color.Couchfin.mist)

            Canvas { context, size in
                let rowHeight = size.height / 2
                let midX = size.width / 2
                let markWidth: CGFloat = UIDevice.isTV ? 4 : 2
                let lateness = -offsetMilliseconds
                // Full deflection at half a second
                let shift = CGFloat(max(-1, min(1, lateness / 500))) * (size.width / 2 - markWidth * 2)

                for row in 0 ..< 2 {
                    let y = rowHeight * (CGFloat(row) + 0.5)
                    context.fill(
                        Path(CGRect(x: 0, y: y - 0.5, width: size.width, height: 1)),
                        with: .color(Color.Couchfin.hairline)
                    )
                }

                let markHeight = rowHeight * 0.7
                let pictureMark = CGRect(
                    x: midX - markWidth / 2,
                    y: rowHeight * 0.5 - markHeight / 2,
                    width: markWidth,
                    height: markHeight
                )
                let soundMark = pictureMark.offsetBy(dx: shift, dy: rowHeight)

                context.fill(Path(pictureMark), with: .color(.white))
                context.fill(Path(soundMark), with: .color(Color.Couchfin.glint))

                guard abs(shift) > markWidth * 2 else { return }

                // Arrow from the sound mark back towards the picture
                let arrowY = rowHeight * 1.5
                let headSize: CGFloat = UIDevice.isTV ? 8 : 4
                let direction: CGFloat = shift > 0 ? -1 : 1
                var arrow = Path()
                arrow.move(to: CGPoint(x: midX + shift + direction * markWidth * 1.5, y: arrowY))
                arrow.addLine(to: CGPoint(x: midX - direction * markWidth, y: arrowY))
                arrow.move(to: CGPoint(x: midX - direction * markWidth - direction * headSize, y: arrowY - headSize * 0.7))
                arrow.addLine(to: CGPoint(x: midX - direction * markWidth, y: arrowY))
                arrow.addLine(to: CGPoint(x: midX - direction * markWidth - direction * headSize, y: arrowY + headSize * 0.7))
                context.stroke(arrow, with: .color(Color.Couchfin.glint), lineWidth: UIDevice.isTV ? 2 : 1)
            }
        }
        .accessibilityHidden(true)
    }
}
