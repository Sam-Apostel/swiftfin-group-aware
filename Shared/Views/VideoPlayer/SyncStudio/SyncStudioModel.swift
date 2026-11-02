//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Foundation
import JellyfinAPI
import SwiftUI

/// State of one visit to the sync studio.
///
/// Opening it pauses playback at `pausedSeconds`. The picture can be stepped frame by frame
/// and the sound slid under it; a check plays only the few seconds around the frame and comes
/// back. Saving or cancelling resumes playback from `pausedSeconds`.
@MainActor
final class SyncStudioModel: ObservableObject {

    enum WaveformState: Equatable {
        case loading
        case loaded(AVSyncWaveform.Envelope)
        case failed
    }

    /// Seconds of sound visible in the strip.
    static let visibleSeconds: Double = 6
    /// How far the sound can be slid, in milliseconds.
    static let offsetRange: ClosedRange<Double> = -3000 ... 3000
    /// How far frame stepping may move away from where playback paused.
    static let maximumStepSeconds: Double = 3
    /// The check plays from 3 s before the frame to 1 s after it.
    static let previewLeadIn: Double = 3
    static let previewTail: Double = 1

    @Published
    private(set) var waveformState: WaveformState = .loading
    /// The candidate offset in the player's convention: positive plays the sound later.
    @Published
    var offsetMilliseconds: Double
    /// The position of the frame on screen.
    @Published
    private(set) var videoSeconds: Double
    @Published
    private(set) var isPreviewing = false
    @Published
    private(set) var correction: AVSyncCorrection?

    let pausedSeconds: Double
    let frameDuration: Double

    private var originalOffset: Duration
    private var isFinished = false
    private var fetchTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?

    private weak var manager: MediaPlayerManager?
    private weak var viewState: VideoPlayer.ViewState?

    init(manager: MediaPlayerManager, viewState: VideoPlayer.ViewState) {
        self.manager = manager
        self.viewState = viewState

        let seconds = manager.seconds.seconds
        self.pausedSeconds = seconds
        self.videoSeconds = seconds
        self.originalOffset = manager.audioOffset
        self.correction = manager.avSync.correction
        self.offsetMilliseconds = clamp(
            Double(manager.audioOffset.microseconds) / 1000,
            min: Self.offsetRange.lowerBound,
            max: Self.offsetRange.upperBound
        )

        let videoStream = manager.playbackItem?.videoStreams.first
        let frameRate = Double(videoStream?.realFrameRate ?? videoStream?.averageFrameRate ?? 24)
        self.frameDuration = 1 / clamp(frameRate.isFinite ? frameRate : 24, min: 10, max: 120)

        manager.avSync.suspend()
        manager.setPlaybackRequestStatus(status: .paused)
        viewState.syncStudio = self

        loadWaveform()
    }

    // MARK: - Derived

    var direction: AVSyncDirection {
        AVSyncDirection(offsetMilliseconds: offsetMilliseconds)
    }

    var addsSecondPoint: Bool {
        correction?.addsSecondPoint(at: videoSeconds) ?? false
    }

    // MARK: - Waveform

    private func loadWaveform() {
        guard let manager,
              let item = manager.playbackItem,
              let itemID = item.baseItem.id,
              let client = manager.userSession?.client
        else {
            waveformState = .failed
            return
        }

        // Room for the visible strip, the full slide range and some frame stepping
        let margin = Self.visibleSeconds / 2 + Self.offsetRange.upperBound / 1000 + 0.5
        let startSeconds = max(0, pausedSeconds - margin)
        let durationSeconds = pausedSeconds + margin - startSeconds
        let mediaSourceID = item.mediaSource.id
        let audioStreamIndex = item.selectedAudioStreamIndex

        fetchTask = Task { [weak self] in
            do {
                let envelope = try await AVSyncWaveformFetcher.fetchEnvelope(
                    itemID: itemID,
                    mediaSourceID: mediaSourceID,
                    audioStreamIndex: audioStreamIndex,
                    startSeconds: startSeconds,
                    durationSeconds: durationSeconds,
                    client: client
                )

                guard !Task.isCancelled else { return }

                self?.waveformState = .loaded(envelope)
            } catch {
                guard !Task.isCancelled else { return }

                self?.manager?.logger.warning("Audio sync: fetching the waveform failed: \(error.localizedDescription)")
                self?.waveformState = .failed
            }
        }
    }

    // MARK: - Frames

    func stepFrame(forward: Bool) {
        guard !isFinished, let manager else { return }

        if isPreviewing {
            stopPreview()
        }

        let target = videoSeconds + (forward ? frameDuration : -frameDuration)
        let lowerBound = max(0, pausedSeconds - Self.maximumStepSeconds)
        let upperBound = pausedSeconds + Self.maximumStepSeconds

        videoSeconds = clamp(target, min: lowerBound, max: upperBound)
        manager.seconds = .seconds(videoSeconds)
        manager.proxy?.setSeconds(.seconds(videoSeconds))
    }

    // MARK: - Check

    func togglePreview() {
        if isPreviewing {
            stopPreview()
        } else {
            startPreview()
        }
    }

    /// Plays from shortly before the frame to just after it with the candidate offset,
    /// then returns to the frame and pauses. Nothing further into the film is played.
    func startPreview() {
        guard !isFinished, !isPreviewing, let manager, let proxy = manager.proxy else { return }

        isPreviewing = true

        let startSeconds = max(0, videoSeconds - Self.previewLeadIn)
        let endSeconds = videoSeconds + Self.previewTail

        manager.audioOffset = .milliseconds(Int64(offsetMilliseconds.rounded()))
        manager.seconds = .seconds(startSeconds)
        proxy.setSeconds(.seconds(startSeconds))
        manager.setPlaybackRequestStatus(status: .playing)

        previewTask = Task { [weak self] in
            // Give the seek a moment, then wait for the end of the clip (with a cap for buffering)
            let deadline = Date.now.addingTimeInterval(15)
            try? await Task.sleep(for: .milliseconds(300))

            while !Task.isCancelled, Date.now < deadline {
                guard let seconds = self?.manager?.seconds.seconds else { return }

                if seconds >= endSeconds {
                    break
                }

                try? await Task.sleep(for: .milliseconds(40))
            }

            guard !Task.isCancelled else { return }

            self?.stopPreview()
        }
    }

    func stopPreview() {
        previewTask?.cancel()
        previewTask = nil

        guard isPreviewing else { return }

        isPreviewing = false

        guard let manager else { return }

        manager.setPlaybackRequestStatus(status: .paused)
        manager.seconds = .seconds(videoSeconds)
        manager.proxy?.setSeconds(.seconds(videoSeconds))
    }

    // MARK: - Save, reset, cancel

    func save() {
        guard !isFinished, let manager else { return }

        let point = AVSyncCorrection.Point(
            seconds: videoSeconds,
            offsetMilliseconds: offsetMilliseconds.rounded()
        )
        let isFirstPoint = correction == nil
        let newCorrection = correction?.adding(point)
            ?? AVSyncCorrection(constantOffsetMilliseconds: point.offsetMilliseconds, at: point.seconds)

        manager.avSync.setCorrection(newCorrection)
        manager.audioOffset = .milliseconds(Int64(newCorrection.offsetMilliseconds(at: pausedSeconds).rounded()))

        finish()

        guard let mediaSourceID = manager.avSync.mediaSourceID, let userSession = manager.userSession else { return }

        let toastProxy = viewState?.toastProxy

        Task {
            do {
                try await AVSyncStore.save(newCorrection, mediaSourceID: mediaSourceID, userSession: userSession)
                toastProxy?.present(
                    isFirstPoint ? L10n.AVSync.savedFirstToast : L10n.AVSync.savedToast,
                    systemName: "checkmark.circle.fill"
                )
            } catch {
                manager.logger.warning("Audio sync: saving the fix failed: \(error.localizedDescription)")
                toastProxy?.present(L10n.AVSync.notSavedToast, systemName: "exclamationmark.icloud")
            }
        }
    }

    /// Forgets the saved fix for this file, here and on the server. The studio stays open.
    func resetSaved() {
        guard !isFinished, let manager else { return }

        correction = nil
        originalOffset = .zero
        offsetMilliseconds = 0
        manager.avSync.setCorrection(nil)

        guard let mediaSourceID = manager.avSync.mediaSourceID, let userSession = manager.userSession else { return }

        let toastProxy = viewState?.toastProxy

        Task {
            do {
                try await AVSyncStore.save(nil, mediaSourceID: mediaSourceID, userSession: userSession)
                toastProxy?.present(L10n.AVSync.resetToast, systemName: "arrow.counterclockwise")
            } catch {
                manager.logger.warning("Audio sync: resetting the fix failed: \(error.localizedDescription)")
                toastProxy?.present(L10n.AVSync.notSavedToast, systemName: "exclamationmark.icloud")
            }
        }
    }

    /// Restores the offset from before the studio opened. Safe to call more than once,
    /// and called when the studio goes away without saving.
    func cancel() {
        guard !isFinished, let manager else { return }

        manager.audioOffset = originalOffset
        finish()
    }

    /// Resumes playback from where it paused and closes the studio.
    private func finish() {
        isFinished = true
        fetchTask?.cancel()
        previewTask?.cancel()
        previewTask = nil
        isPreviewing = false

        if let viewState, viewState.syncStudio === self {
            viewState.syncStudio = nil
        }

        guard let manager else { return }

        manager.seconds = .seconds(pausedSeconds)
        manager.proxy?.setSeconds(.seconds(pausedSeconds))
        manager.avSync.resume()
        manager.setPlaybackRequestStatus(status: .playing)

        if let viewState, viewState.selectedSupplementID == SyncStudioSupplement.supplementID {
            viewState.hideControls()
        }
    }

    // MARK: - Remote

    /// Select on the waveform saves. Returns whether the press was used.
    func handleSelect() -> Bool {
        guard !isFinished,
              let viewState,
              viewState.focusCoordinator.focusedIDs.contains(SyncStudioSupplement.waveformFocusID)
        else { return false }

        save()
        return true
    }
}
