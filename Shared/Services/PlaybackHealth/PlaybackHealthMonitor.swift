//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Defaults
import FactoryKit
import Foundation
import JellyfinAPI
import Logging
import UIKit

/// A player that can read further ahead while playing.
@MainActor
protocol MediaPlayerBufferConfigurable {
    func setSteadyPlayback(_ isEnabled: Bool)
}

extension Container {

    var playbackHealthMonitor: Factory<PlaybackHealthMonitor> {
        self { @MainActor in PlaybackHealthMonitor() }
            .singleton
    }
}

/// Watches the video player for rebuffering stalls, works out why they happen,
/// turns on steady playback for direct-play stalls, and reports items that need a lighter copy.
///
/// Attached once per player launch from `NavigationRoute.videoPlayer(manager:)`.
@MainActor
final class PlaybackHealthMonitor: ObservableObject {

    /// How often the server session is polled while transcoding.
    private static let sessionPollInterval: TimeInterval = 10
    /// Samples kept for the diagnosis.
    private static let maxSamples = 30

    @Published
    private(set) var stallCount = 0
    @Published
    private(set) var diagnosis: PlaybackHealthDiagnosis?
    @Published
    private(set) var latestSample: PlaybackHealthTranscodeSample?
    @Published
    private(set) var isSteadyPlayback = false
    /// Whether the gentle "that stuttered" note should show (paused, after enough stalls).
    @Published
    private(set) var isPresentingStutterNote = false

    /// The video's framerate, to compare with the server's conversion speed.
    private(set) var sourceFramerate: Double?
    private(set) var isTranscoding = false

    private let logger = Logger.swiftfin()

    private var cancellables = Set<AnyCancellable>()
    private var detector = PlaybackStallDetector()
    private var samples: [PlaybackHealthTranscodeSample] = []
    private var sessionTask: Task<Void, Never>?
    private var lastSessionPoll: Date = .distantPast
    private var reportedStallCount = 0
    private var hasShownStutterNote = false

    private weak var manager: MediaPlayerManager?
    private var playbackItem: MediaPlayerItem?
    private var item: BaseItemDto?

    // MARK: - Attach

    func attach(to manager: MediaPlayerManager) {
        finishSession()

        cancellables = []
        self.manager = manager

        // `@Published` emits in `willSet`: the new item is passed in.
        manager.$playbackItem
            .sink { [weak self] newItem in
                self?.playbackItemWillChange(to: newItem)
            }
            .store(in: &cancellables)

        manager.actions
            .sink { [weak self] action in
                switch action {
                case .stop, .error:
                    self?.detach()
                default: ()
                }
            }
            .store(in: &cancellables)

        Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in
                self?.tick(at: date)
            }
            .store(in: &cancellables)

        Notifications[.applicationWillTerminate]
            .publisher
            .sink { [weak self] _ in
                self?.finishSession()
            }
            .store(in: &cancellables)
    }

    private func detach() {
        finishSession()

        cancellables = []
        sessionTask?.cancel()
        sessionTask = nil
        manager = nil
    }

    // MARK: - Session

    private func playbackItemWillChange(to newItem: MediaPlayerItem?) {
        guard let newItem else { return }

        if newItem.baseItem.id != item?.id {
            finishSession()
            startSession(with: newItem)
        } else {
            // Track or bitrate change: same item, new stream.
            playbackItem = newItem
            isTranscoding = newItem.mediaSource.transcodingURL != nil
            samples = []
            detector.restartGrace(at: Date.now.timeIntervalSinceReferenceDate, duration: PlaybackStallDetector.startGrace)
        }
    }

    private func startSession(with newItem: MediaPlayerItem) {
        playbackItem = newItem
        item = newItem.baseItem
        isTranscoding = newItem.mediaSource.transcodingURL != nil
        sourceFramerate = newItem.videoStreams.first.flatMap { stream in
            (stream.realFrameRate ?? stream.averageFrameRate).map(Double.init)
        }

        detector = PlaybackStallDetector(startingAt: Date.now.timeIntervalSinceReferenceDate)
        samples = []
        lastSessionPoll = .distantPast
        reportedStallCount = 0
        hasShownStutterNote = false

        stallCount = 0
        diagnosis = nil
        latestSample = nil
        isPresentingStutterNote = false
        isSteadyPlayback = !newItem.isOffline && PlaybackHealthMemory.isSteadyPlayback(for: newItem.baseItem.id)
    }

    /// Remembers and reports the session if it stuttered, then forgets it.
    private func finishSession() {
        if stallCount >= PlaybackHealthClassifier.stallsWorthReporting {
            report()
        }

        sessionTask?.cancel()
        sessionTask = nil
        item = nil
        playbackItem = nil
        isPresentingStutterNote = false
    }

    // MARK: - Sampling

    private func tick(at date: Date) {
        guard let manager, let playbackItem, manager.state == .playback else { return }

        let wantsToPlay = manager.playbackRequestStatus == .playing

        let didStall = detector.sample(
            at: date.timeIntervalSinceReferenceDate,
            position: manager.seconds.seconds,
            isBuffering: manager.proxy?.isBuffering.value ?? false,
            wantsToPlay: wantsToPlay,
            rate: manager.rate
        )

        if didStall {
            stallCount = detector.stallCount
            stallDidHappen()
        }

        if isTranscoding, !playbackItem.isOffline, date.timeIntervalSince(lastSessionPoll) >= Self.sessionPollInterval {
            lastSessionPoll = date
            pollSession(itemID: playbackItem.baseItem.id, runtime: playbackItem.baseItem.runtime?.seconds)
        }

        updateStutterNote(wantsToPlay: wantsToPlay)
    }

    private func updateStutterNote(wantsToPlay: Bool) {
        let shouldPresent = !wantsToPlay
            && stallCount >= PlaybackHealthClassifier.stallsWorthReporting
            && !hasShownStutterNote

        if isPresentingStutterNote, wantsToPlay {
            // Shown once per session: resuming dismisses it for good.
            hasShownStutterNote = true
            isPresentingStutterNote = false
        } else if shouldPresent != isPresentingStutterNote {
            isPresentingStutterNote = shouldPresent
        }
    }

    private func stallDidHappen() {
        logger.info("Playback stalled", metadata: ["stalls": .stringConvertible(stallCount)])

        diagnosis = PlaybackHealthDiagnoser.diagnose(
            isTranscoding: isTranscoding,
            samples: samples,
            sourceFramerate: sourceFramerate,
            playbackRate: manager?.rate ?? 1
        )

        guard stallCount >= PlaybackHealthClassifier.stallsWorthReporting else { return }

        // A bigger read-ahead buffer helps when the network, not the server, is the bottleneck.
        if diagnosis == .network, Defaults[.PlaybackHealth.steadyPlayback], playbackItem?.isOffline == false, !isSteadyPlayback {
            isSteadyPlayback = true
            (manager?.proxy as? MediaPlayerBufferConfigurable)?.setSteadyPlayback(true)
        }

        // Report as soon as it's clearly stuttering, in case the session doesn't end cleanly.
        if reportedStallCount == 0 {
            report()
        }
    }

    private func pollSession(itemID: String?, runtime: Double?) {
        guard let userSession = Container.shared.currentUserSession() else { return }

        let deviceID = userSession.client.configuration.deviceID
        let request = Paths.getSessions(parameters: .init(deviceID: deviceID))

        sessionTask?.cancel()
        sessionTask = Task { [weak self] in
            guard let sessions = try? await userSession.client.send(request).value else { return }

            let session = sessions.first { $0.nowPlayingItem?.id == itemID } ?? sessions.first

            guard let info = session?.transcodingInfo, let self, !Task.isCancelled else { return }

            let sample = PlaybackHealthTranscodeSample(
                framerate: info.framerate.map(Double.init),
                completionPercentage: info.completionPercentage,
                isVideoDirect: info.isVideoDirect,
                playheadSeconds: self.manager?.seconds.seconds ?? 0,
                runtimeSeconds: runtime
            )

            self.add(sample)
        }
    }

    private func add(_ sample: PlaybackHealthTranscodeSample) {
        latestSample = sample
        samples.append(sample)

        if samples.count > Self.maxSamples {
            samples.removeFirst(samples.count - Self.maxSamples)
        }

        if stallCount > 0 {
            diagnosis = PlaybackHealthDiagnoser.diagnose(
                isTranscoding: isTranscoding,
                samples: samples,
                sourceFramerate: sourceFramerate,
                playbackRate: manager?.rate ?? 1
            )
        }
    }

    // MARK: - Reporting

    /// Remembers the stalls on this device and adds the item to the user's "needs a lighter copy" list.
    private func report() {
        guard let item, let itemID = item.id, stallCount > reportedStallCount else { return }

        reportedStallCount = stallCount
        PlaybackHealthMemory.recordStalls(stallCount, for: itemID)

        guard let playbackItem, !playbackItem.isOffline, let userSession = Container.shared.currentUserSession() else { return }

        let verdict = PlaybackHealthClassifier.verdict(
            for: PlaybackHealthInput(
                mediaSource: playbackItem.mediaSource,
                isServerDecision: true,
                deviceProfile: playbackItem.deviceProfile,
                device: .current,
                maxBitrate: PlaybackHealthCheck.maxBitrate(for: playbackItem.requestedBitrate),
                audioStreamIndex: playbackItem.selectedAudioStreamIndex,
                subtitleStreamIndex: playbackItem.selectedSubtitleStreamIndex,
                stalledBefore: stallCount
            )
        )

        let diagnosis = diagnosis ?? .unknown
        let name = item.seriesName.map { "\($0) · \(item.displayTitle)" } ?? item.displayTitle

        let entry = LighterCopyEntry(
            id: itemID,
            name: name,
            reason: L10n.PlaybackHealth.diagnosisDescription(diagnosis, reasons: verdict.reasons),
            target: verdict.target.map(L10n.PlaybackHealth.targetDescription) ?? "",
            diagnosis: diagnosis,
            stalls: stallCount,
            updatedAt: .now,
            reportedBy: userSession.user.username,
            device: UIDevice.current.model
        )

        let logger = self.logger

        Task {
            do {
                try await LighterCopyStore.apply([itemID: entry], userID: userSession.user.id, client: userSession.client)
            } catch {
                logger.warning("Unable to save the lighter copy list: \(error.localizedDescription)")
            }
        }
    }
}
