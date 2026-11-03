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
/// Opening it pauses playback at `pausedSeconds`. The picture can be scrubbed or stepped frame
/// by frame and the sound slid under it; a check plays only the few seconds around the frame
/// and comes back. Saving or cancelling returns to `pausedSeconds` as playback was before.
///
/// While the studio is open it owns the player: it holds the player paused (or playing during a
/// check) against anything else that asks, and follows the position if something else moves it,
/// like a remote command or a keyboard shortcut.
@MainActor
final class SyncStudioModel: ObservableObject {

    enum WaveformStatus: Equatable {
        case loading
        case ready
        case failed
    }

    /// Seconds of sound visible in the strip.
    static let visibleSeconds: Double = 6
    /// How far the sound can be slid, in milliseconds.
    static let offsetRange: ClosedRange<Double> = -3000 ... 3000
    /// The check plays from 3 s before the frame to 1 s after it.
    static let previewLeadIn: Double = 3
    static let previewTail: Double = 1
    /// Staying this far from the end keeps a check or a scrub from ending the film.
    private static let endMargin: Double = 2
    /// One seek at a time while scrubbing.
    private static let seekInterval: Duration = .milliseconds(100)
    /// How long a seek gets to land before the player's own position is believed again.
    private static let seekSettle: Duration = .milliseconds(600)
    private static let seekSettleLimit: TimeInterval = 8
    /// Fetched beyond what the strip and the slide range can show, to scrub a little without fetching again.
    private static let waveformSlack: Double = 8

    @Published
    private(set) var waveformStatus: WaveformStatus = .loading
    @Published
    private(set) var envelope: AVSyncWaveform.Envelope?
    /// The candidate offset in the player's convention: positive plays the sound later.
    @Published
    private(set) var offsetMilliseconds: Double
    /// The position of the frame on screen.
    @Published
    private(set) var videoSeconds: Double
    @Published
    private(set) var isPreviewing = false
    @Published
    private(set) var correction: AVSyncCorrection?

    let pausedSeconds: Double
    let frameDuration: Double
    let runtimeSeconds: Double?

    private let wasPlaying: Bool
    private let startingItem: MediaPlayerItem?

    private var originalOffset: Duration
    private var isFinished = false
    private var waveformTask: Task<Void, Never>?
    private var waveformRange: ClosedRange<Double>?
    private var previewTask: Task<Void, Never>?

    private var pendingSeek: Double?
    private var seekTask: Task<Void, Never>?
    private var seekSettleTask: Task<Void, Never>?

    private var cancellables: Set<AnyCancellable> = []

    private weak var manager: MediaPlayerManager?
    private weak var viewState: VideoPlayer.ViewState?

    init(manager: MediaPlayerManager, viewState: VideoPlayer.ViewState) {
        self.manager = manager
        self.viewState = viewState

        let seconds = manager.seconds.seconds
        self.pausedSeconds = seconds
        self.videoSeconds = seconds
        self.wasPlaying = manager.playbackRequestStatus == .playing
        self.startingItem = manager.playbackItem
        self.originalOffset = manager.audioOffset
        self.correction = manager.avSync.correction
        self.runtimeSeconds = manager.item.runtime?.seconds
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

        observe(manager)
        loadWaveform(at: seconds, debounced: false)
    }

    // MARK: - Derived

    var direction: AVSyncDirection {
        AVSyncDirection(offsetMilliseconds: offsetMilliseconds)
    }

    var addsSecondPoint: Bool {
        correction?.addsSecondPoint(at: videoSeconds) ?? false
    }

    /// The film's length as far as the player can be moved.
    var scrubbableSeconds: Double {
        guard let runtimeSeconds, runtimeSeconds > Self.endMargin else {
            return max(videoSeconds, pausedSeconds) + 3600
        }

        return runtimeSeconds - Self.endMargin
    }

    /// Whether the fetched sound covers what the strip shows right now.
    var isWaveformVisible: Bool {
        guard let envelope else { return false }

        let centerSeconds = videoSeconds - offsetMilliseconds / 1000
        return envelope.endSeconds > centerSeconds - Self.visibleSeconds / 2
            && envelope.startSeconds < centerSeconds + Self.visibleSeconds / 2
    }

    // MARK: - Holding the player

    private func observe(_ manager: MediaPlayerManager) {
        manager.$playbackRequestStatus
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.holdPlaybackStatus()
            }
            .store(in: &cancellables)

        manager.secondsBox
            .$value
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.followPlayerPosition()
            }
            .store(in: &cancellables)

        manager.$playbackItem
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] item in
                guard let self, item !== startingItem else { return }

                abandon()
            }
            .store(in: &cancellables)

        manager.$state
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard state == .stopped else { return }

                self?.abandon()
            }
            .store(in: &cancellables)
    }

    /// The players report their state back to the manager, sometimes late: a stale "paused" after
    /// a seek would otherwise stop a check, and anything else can ask to play. Only the studio decides.
    private func holdPlaybackStatus() {
        guard !isFinished, let manager else { return }

        let wanted: MediaPlayerManager.PlaybackRequestStatus = isPreviewing ? .playing : .paused

        if manager.playbackRequestStatus != wanted {
            manager.setPlaybackRequestStatus(status: wanted)
        }
    }

    /// Something other than the studio moved the player, or a seek landed somewhere else than asked.
    /// Positions from before a seek has landed say nothing, so they wait until it settled.
    private func followPlayerPosition() {
        guard !isFinished,
              !isPreviewing,
              seekTask == nil,
              seekSettleTask == nil,
              let seconds = manager?.seconds.seconds,
              abs(seconds - videoSeconds) > max(frameDuration * 2, 0.25)
        else { return }

        videoSeconds = seconds
        loadWaveform(at: seconds, debounced: true)
    }

    // MARK: - Seeking

    private func requestSeek(to seconds: Double) {
        seekSettleTask?.cancel()
        seekSettleTask = nil
        pendingSeek = seconds

        guard seekTask == nil else { return }

        seekTask = Task { [weak self] in
            while let self, !Task.isCancelled, let seconds = pendingSeek {
                pendingSeek = nil
                manager?.proxy?.setSeconds(.seconds(seconds))

                try? await Task.sleep(for: Self.seekInterval)
            }

            guard !Task.isCancelled else { return }

            self?.seekTask = nil
            self?.settleSeek()
        }
    }

    private func settleSeek() {
        seekSettleTask = Task { [weak self] in
            try? await Task.sleep(for: Self.seekSettle)

            let deadline = Date.now.addingTimeInterval(Self.seekSettleLimit)

            while !Task.isCancelled, Date.now < deadline, self?.manager?.proxy?.isBuffering.value == true {
                try? await Task.sleep(for: .milliseconds(100))
            }

            guard !Task.isCancelled else { return }

            self?.seekSettleTask = nil
            self?.followPlayerPosition()
        }
    }

    private func cancelSeeks() {
        pendingSeek = nil
        seekTask?.cancel()
        seekTask = nil
        seekSettleTask?.cancel()
        seekSettleTask = nil
    }

    private func clampedToFilm(_ seconds: Double) -> Double {
        clamp(seconds, min: 0, max: scrubbableSeconds)
    }

    // MARK: - Picture

    func scrub(to seconds: Double) {
        guard !isFinished, seconds.isFinite else { return }

        stopPreview()

        let target = clampedToFilm(seconds)
        guard target != videoSeconds else { return }

        videoSeconds = target
        requestSeek(to: target)
        loadWaveform(at: target, debounced: true)
    }

    func stepFrame(forward: Bool) {
        guard !isFinished else { return }

        stopPreview()

        let target = clampedToFilm(videoSeconds + (forward ? frameDuration : -frameDuration))
        guard target != videoSeconds else { return }

        videoSeconds = target
        // An exact seek shows the first frame at or after the target. Aiming a little early
        // keeps rounding from skipping past the next frame.
        requestSeek(to: max(0, target - frameDuration * 0.1))
        loadWaveform(at: target, debounced: true)
    }

    // MARK: - Sound

    func slideSound(toMilliseconds milliseconds: Double) {
        guard !isFinished else { return }

        stopPreview()
        offsetMilliseconds = clamp(milliseconds, min: Self.offsetRange.lowerBound, max: Self.offsetRange.upperBound)
    }

    private func loadWaveform(at seconds: Double, debounced: Bool) {
        let margin = Self.visibleSeconds / 2 + Self.offsetRange.upperBound / 1000
        let needed = max(0, seconds - margin) ... seconds + margin

        if let waveformRange, waveformRange.contains(needed.lowerBound), waveformRange.contains(needed.upperBound) {
            return
        }

        guard let manager,
              let item = manager.playbackItem,
              let itemID = item.baseItem.id,
              let client = manager.userSession?.client
        else {
            waveformStatus = .failed
            return
        }

        let range = max(0, seconds - margin - Self.waveformSlack) ... seconds + margin + Self.waveformSlack
        let mediaSourceID = item.mediaSource.id
        let audioStreamIndex = item.selectedAudioStreamIndex

        waveformTask?.cancel()
        waveformRange = range
        waveformStatus = .loading

        waveformTask = Task { [weak self] in
            if debounced {
                try? await Task.sleep(for: .milliseconds(300))
            }

            guard !Task.isCancelled else { return }

            do {
                let envelope = try await AVSyncWaveformFetcher.fetchEnvelope(
                    itemID: itemID,
                    mediaSourceID: mediaSourceID,
                    audioStreamIndex: audioStreamIndex,
                    startSeconds: range.lowerBound,
                    durationSeconds: range.upperBound - range.lowerBound,
                    client: client
                )

                guard !Task.isCancelled else { return }

                self?.envelope = envelope
                self?.waveformStatus = .ready
            } catch {
                guard !Task.isCancelled else { return }

                self?.manager?.logger.warning("Audio sync: fetching the waveform failed: \(error.localizedDescription)")
                self?.waveformRange = nil
                self?.waveformStatus = .failed
            }
        }
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

        cancelSeeks()
        isPreviewing = true

        let startSeconds = max(0, videoSeconds - Self.previewLeadIn)
        let endSeconds = videoSeconds + Self.previewTail

        manager.audioOffset = .milliseconds(Int64(offsetMilliseconds.rounded()))
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

        holdPlaybackStatus()
        requestSeek(to: videoSeconds)
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

        stopPreview()
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

    /// Stops holding the player and closes the studio.
    private func close() {
        isFinished = true
        cancellables.removeAll()
        waveformTask?.cancel()
        previewTask?.cancel()
        previewTask = nil
        isPreviewing = false
        cancelSeeks()

        if let viewState, viewState.syncStudio === self {
            viewState.syncStudio = nil
        }
    }

    /// Returns to where playback paused, as it was, and closes the studio.
    private func finish() {
        close()

        guard let manager else { return }

        manager.seconds = .seconds(pausedSeconds)
        manager.proxy?.setSeconds(.seconds(pausedSeconds))
        manager.avSync.resume()
        manager.setPlaybackRequestStatus(status: wasPlaying ? .playing : .paused)

        dismiss()
    }

    /// The film changed or stopped underneath the studio: there's nothing to return to.
    private func abandon() {
        guard !isFinished else { return }

        close()

        manager?.audioOffset = originalOffset
        manager?.avSync.resume()

        dismiss()
    }

    private func dismiss() {
        if let viewState, viewState.isPresentingSyncStudio {
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
