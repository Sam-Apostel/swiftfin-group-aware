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

    static var pictureFocusID: String {
        "\(VideoPlayer.ViewState.Focus.supplementContent(supplementID)).picture"
    }

    /// The height of the panel's content on a screen of this size. The picture gets the rest.
    static func contentHeight(in size: CGSize) -> CGFloat {
        if UIDevice.isTV {
            return 470
        }

        if size.height < 500 {
            return 196
        }

        return size.width < 560 ? 372 : 316
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

    @Environment(\.verticalSizeClass)
    private var verticalSizeClass

    @Environment(VideoPlayer.ViewState.self)
    private var viewState

    @ObservedObject
    var model: SyncStudioModel

    @State
    private var pictureStripSize: CGSize = .zero
    @State
    private var scrubStartSeconds: Double?
    @GestureState
    private var isScrubbingPicture = false

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
                model.slideSound(toMilliseconds: newValue * sliderUnit + Model.offsetRange.lowerBound)
            }
        )
    }

    /// An iPhone on its side: every point of height goes to the strips.
    private var isShort: Bool {
        !UIDevice.isTV && verticalSizeClass == .compact
    }

    private var spacing: CGFloat {
        if UIDevice.isTV {
            return 20
        }

        return isShort ? 6 : 10
    }

    private var pictureStripHeight: CGFloat {
        if UIDevice.isTV {
            return 72
        }

        return isShort ? 38 : 48
    }

    private var waveformHeight: CGFloat {
        if UIDevice.isTV {
            return 130
        }

        return isShort ? 56 : 76
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

    private var direction: some View {
        HStack(spacing: UIDevice.isTV ? 16 : 8) {
            SyncDirectionDiagram(offsetMilliseconds: model.offsetMilliseconds)
                .frame(width: UIDevice.isTV ? 150 : 72, height: UIDevice.isTV ? 54 : 28)

            directionText
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .font(UIDevice.isTV ? .callout : .footnote)
        .accessibilityElement(children: .combine)
    }

    /// The saved fix sits beside the direction where there's room, above it where there isn't.
    @ViewBuilder
    private var statusRow: some View {
        if model.correction == nil {
            HStack(spacing: 0) {
                direction

                Spacer(minLength: 0)
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: spacing) {
                    direction

                    Spacer(minLength: spacing)

                    savedStatus
                }

                VStack(alignment: .leading, spacing: spacing) {
                    savedStatus

                    direction
                }
            }
            .syncStudioFocusSection()
        }
    }

    // MARK: - Picture

    private var pictureSeconds: Binding<Double> {
        Binding(
            get: { model.videoSeconds },
            set: { model.scrub(to: $0) }
        )
    }

    private var secondsPerPoint: Double {
        pictureStripSize.width > 0 ? SyncPictureStrip.visibleSeconds / pictureStripSize.width : 0
    }

    #if os(iOS)
    /// Dragging moves the ruler under the line, and a flick carries on past the finger.
    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .updating($isScrubbingPicture) { _, isScrubbing, _ in
                isScrubbing = true
            }
            .onChanged { value in
                let start = scrubStartSeconds ?? model.videoSeconds
                scrubStartSeconds = start
                model.scrub(to: start - value.translation.width * secondsPerPoint)
            }
            .onEnded { value in
                let carry = value.predictedEndTranslation.width - value.translation.width

                if abs(carry) > 40 {
                    model.scrub(to: model.videoSeconds - carry * secondsPerPoint)
                }
            }
    }
    #endif

    private var pictureStrip: some View {
        Group {
            #if os(tvOS)
            SliderContainer(
                value: pictureSeconds,
                total: model.scrubbableSeconds
            )
            .sliderContainerStyle(SyncPictureSliderStyle())
            .syncStudioFocus(SyncStudioSupplement.pictureFocusID)
            .focusSection()
            #else
            SyncPictureStrip(
                seconds: model.videoSeconds,
                isFocused: false,
                isEditing: isScrubbingPicture
            )
            .contentShape(Rectangle())
            .highPriorityGesture(scrubGesture)
            .trackingSize($pictureStripSize)
            .onChange(of: isScrubbingPicture) {
                if !isScrubbingPicture {
                    scrubStartSeconds = nil
                }
            }
            #endif
        }
        .frame(height: pictureStripHeight)
        .accessibilityElement()
        .accessibilityLabel(L10n.AVSync.picture)
        .accessibilityValue(Duration.seconds(model.videoSeconds).formatted(.time(pattern: .hourMinuteSecond)))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: model.scrub(to: model.videoSeconds + 1)
            case .decrement: model.scrub(to: model.videoSeconds - 1)
            @unknown default: break
            }
        }
    }

    // MARK: - Waveform

    @ViewBuilder
    private var waveformMessage: some View {
        if !model.isWaveformVisible {
            switch model.waveformStatus {
            case .loading:
                HStack(spacing: 8) {
                    ProgressView()
                    Text(L10n.AVSync.listening)
                }

            case .failed:
                Text(L10n.AVSync.waveformFailed)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

            case .ready:
                EmptyView()
            }
        }
    }

    private var waveform: some View {
        SliderContainer(
            value: sliderValue,
            total: sliderTotal
        )
        .sliderContainerStyle(
            SyncWaveformSliderStyle(
                envelope: model.envelope,
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
            case .increment: model.slideSound(toMilliseconds: model.offsetMilliseconds + 10)
            case .decrement: model.slideSound(toMilliseconds: model.offsetMilliseconds - 10)
            @unknown default: break
            }
        }
    }

    // MARK: - Controls

    private var frameAndCheckButtons: some View {
        HStack(spacing: UIDevice.isTV ? 24 : 8) {
            Button {
                model.stepFrame(forward: false)
            } label: {
                Label(L10n.AVSync.previousFrame, systemImage: "backward.frame")
                    .labelStyle(.iconOnly)
                    .frame(minWidth: UIDevice.isTV ? nil : 28)
            }
            .buttonRepeatBehavior(.enabled)

            Button {
                model.stepFrame(forward: true)
            } label: {
                Label(L10n.AVSync.nextFrame, systemImage: "forward.frame")
                    .labelStyle(.iconOnly)
                    .frame(minWidth: UIDevice.isTV ? nil : 28)
            }
            .buttonRepeatBehavior(.enabled)

            Button {
                model.togglePreview()
            } label: {
                Label(
                    model.isPreviewing ? L10n.AVSync.stop : L10n.AVSync.check,
                    systemImage: model.isPreviewing ? "stop.fill" : "play.fill"
                )
            }
        }
    }

    private var finishButtons: some View {
        HStack(spacing: UIDevice.isTV ? 24 : 8) {
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
    }

    private var controlsInOneRow: some View {
        HStack(spacing: 0) {
            frameAndCheckButtons

            Spacer(minLength: 16)

            finishButtons
        }
    }

    private var controlsInTwoRows: some View {
        VStack(alignment: .leading, spacing: spacing) {
            frameAndCheckButtons

            finishButtons
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    /// On touch the buttons are a full 44 points tall: a near miss lands on nothing.
    private var controls: some View {
        Group {
            if UIDevice.isTV {
                controlsInOneRow
            } else {
                ViewThatFits(in: .horizontal) {
                    controlsInOneRow

                    controlsInTwoRows
                }
                .font(.subheadline)
            }
        }
        .buttonStyle(.capsule)
        .controlSize(UIDevice.isTV ? .large : .extraLarge)
        .foregroundStyle(.white)
        .syncStudioFocusSection()
    }

    private var hint: String? {
        guard !isShort else { return nil }

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
            statusRow

            pictureStrip

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
    }

    /// Clipped, unlike `scrollIfLargerThanContainer`: a button drawn past the panel can't be tapped.
    var iOSView: some View {
        ScrollView {
            content
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.never)
        .padding(.bottom, safeAreaInsets.bottom)
    }

    var tvOSView: some View {
        content
            .scrollIfLargerThanContainer()
            .padding(.bottom, safeAreaInsets.bottom)
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
            let focusedIDs = viewState.focusCoordinator.focusedIDs

            guard press.phase == .ended,
                  press.type == .leftArrow || press.type == .rightArrow,
                  focusedIDs.contains(SyncStudioSupplement.waveformFocusID) || focusedIDs.contains(SyncStudioSupplement.pictureFocusID)
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
