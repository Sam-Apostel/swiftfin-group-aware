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
import Logging

/// Applies the saved audio sync fix of the playing file.
///
/// Loads the fix when an item starts, after the manager has reset its offsets, and sets
/// `MediaPlayerManager.audioOffset`. A fix with two points (drift) is followed as playback moves:
/// checked every 5 seconds of playback (or on a seek), updated only when it changes by 5 ms or more.
@MainActor
final class AVSyncController {

    /// Playback has to move this far before a drifting offset is checked again.
    static let updateIntervalSeconds: Double = 5
    /// Smaller changes are not worth a glitch in the audio.
    static let minimumChangeMilliseconds: Double = 5

    private(set) var correction: AVSyncCorrection?
    private(set) var mediaSourceID: String?

    /// While the sync studio is open it owns the offset.
    private(set) var isSuspended = false

    private weak var manager: MediaPlayerManager?
    private var loadTask: Task<Void, Never>?
    private var secondsCancellable: AnyCancellable?
    private var lastEvaluatedSeconds: Double?
    private let logger = Logger.swiftfin()

    init(manager: MediaPlayerManager) {
        self.manager = manager
    }

    /// Call after the manager reset its offsets for a new item.
    func itemDidChange(_ item: MediaPlayerItem) {
        loadTask?.cancel()
        correction = nil
        isSuspended = false
        lastEvaluatedSeconds = nil
        observeSeconds()

        let mediaSourceID = item.mediaSource.id ?? item.baseItem.id
        self.mediaSourceID = mediaSourceID

        guard let mediaSourceID,
              !item.baseItem.isLiveStream,
              let userSession = manager?.userSession
        else { return }

        loadTask = Task { [weak self] in
            do {
                let loaded = try await AVSyncStore.load(mediaSourceID: mediaSourceID, userSession: userSession)

                guard !Task.isCancelled, let self, self.mediaSourceID == mediaSourceID else { return }

                self.correction = loaded
                self.applyNow()
            } catch {
                guard !Task.isCancelled else { return }

                self?.logger.warning("Audio sync: loading the saved fix failed: \(error.localizedDescription)")
            }
        }
    }

    /// Stops following the saved fix, so the sync studio can try offsets.
    func suspend() {
        isSuspended = true
    }

    /// Follows the saved fix again and applies it for the current position.
    func resume() {
        isSuspended = false
        lastEvaluatedSeconds = nil
        applyNow()
    }

    /// Replaces the fix (after the studio saved or reset it) without applying it.
    func setCorrection(_ correction: AVSyncCorrection?) {
        loadTask?.cancel()
        self.correction = correction
        lastEvaluatedSeconds = nil
    }

    /// The offset the fix asks for at `seconds`, in milliseconds.
    func offsetMilliseconds(at seconds: Double) -> Double? {
        correction?.offsetMilliseconds(at: seconds)
    }

    // MARK: - Applying

    private func observeSeconds() {
        guard secondsCancellable == nil, let manager else { return }

        let secondsPublisher = manager.secondsBox.$value

        secondsCancellable = secondsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] seconds in
                self?.secondsDidChange(seconds)
            }
    }

    private func secondsDidChange(_ seconds: Duration) {
        guard !isSuspended, let correction, correction.hasDrift else { return }

        let seconds = seconds.seconds
        if let lastEvaluatedSeconds, abs(seconds - lastEvaluatedSeconds) < Self.updateIntervalSeconds {
            return
        }

        apply(correction, at: seconds, minimumChange: Self.minimumChangeMilliseconds)
    }

    private func applyNow() {
        guard !isSuspended, let manager, let correction else { return }

        apply(correction, at: manager.seconds.seconds, minimumChange: 0.5)
    }

    private func apply(_ correction: AVSyncCorrection, at seconds: Double, minimumChange: Double) {
        guard let manager else { return }

        lastEvaluatedSeconds = seconds

        let target = correction.offsetMilliseconds(at: seconds)
        let current = Double(manager.audioOffset.microseconds) / 1000

        guard abs(target - current) >= minimumChange else { return }

        manager.audioOffset = .milliseconds(Int64(target.rounded()))
    }
}
