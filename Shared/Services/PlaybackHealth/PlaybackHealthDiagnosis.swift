//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

// MARK: - Diagnosis

/// The most likely cause of rebuffering stalls in a playback session.
enum PlaybackHealthDiagnosis: String, Codable {

    /// The server converts the video slower than it plays.
    case serverTooSlow
    /// The file plays directly (or the video is copied), so the network couldn't keep up with its bitrate.
    case network
    /// Not enough information yet.
    case unknown
}

// MARK: - Transcode Sample

/// One reading of the server's transcoding progress for this device's session.
struct PlaybackHealthTranscodeSample: Equatable {

    /// Frames per second the server converts at.
    var framerate: Double?
    /// How much of the item the server has converted, 0 to 100.
    var completionPercentage: Double?
    /// Whether the video is copied rather than re-encoded.
    var isVideoDirect: Bool?
    /// The playhead when the sample was taken.
    var playheadSeconds: Double
    var runtimeSeconds: Double?

    /// How far the converted part is ahead of the playhead, when known.
    var leadSeconds: Double? {
        guard let completionPercentage, let runtimeSeconds, runtimeSeconds > 0 else { return nil }

        return completionPercentage / 100 * runtimeSeconds - playheadSeconds
    }
}

// MARK: - Diagnoser

enum PlaybackHealthDiagnoser {

    /// A server ahead of the playback by this much is keeping up, even if it reports a low framerate.
    static let comfortableLeadSeconds: Double = 30
    /// The server must convert at least this fraction of the needed framerate.
    static let framerateTolerance: Double = 0.95
    /// Used when the video's framerate is unknown.
    static let fallbackFramerate: Double = 24

    /// Whether one sample shows the server falling behind.
    static func isFallingBehind(
        _ sample: PlaybackHealthTranscodeSample,
        sourceFramerate: Double?,
        playbackRate: Double
    ) -> Bool {
        guard sample.isVideoDirect != true, let framerate = sample.framerate else { return false }

        if let lead = sample.leadSeconds, lead >= comfortableLeadSeconds {
            return false
        }

        let needed = (sourceFramerate ?? fallbackFramerate) * max(playbackRate, 1)
        return framerate < needed * framerateTolerance
    }

    static func diagnose(
        isTranscoding: Bool,
        samples: [PlaybackHealthTranscodeSample],
        sourceFramerate: Double?,
        playbackRate: Double
    ) -> PlaybackHealthDiagnosis {
        guard isTranscoding else { return .network }

        let videoSamples = samples.filter { $0.isVideoDirect != true }

        // The server only repackages: re-encoding isn't the bottleneck.
        if samples.isNotEmpty, videoSamples.isEmpty {
            return .network
        }

        guard videoSamples.isNotEmpty else { return .unknown }

        let behind = videoSamples.reduce(0) { total, sample in
            isFallingBehind(sample, sourceFramerate: sourceFramerate, playbackRate: playbackRate) ? total + 1 : total
        }

        // A third of the readings is enough: framerates dip and recover while throttled.
        return behind * 3 >= videoSamples.count ? .serverTooSlow : .network
    }
}

// MARK: - Stall Detector

/// Counts rebuffering stalls from once-a-second samples of the player.
///
/// A stall is the player buffering while the viewer wants to play and the playhead not moving.
/// The first seconds after starting and after a seek are ignored: buffering there is expected.
struct PlaybackStallDetector {

    static let startGrace: TimeInterval = 10
    static let seekGrace: TimeInterval = 6
    /// A stall counts once it has lasted this long.
    static let minimumStall: TimeInterval = 1
    /// A playhead jump larger than this, beyond what playback explains, is a seek.
    static let seekThreshold: Double = 4

    private(set) var stallCount = 0
    private(set) var totalStallSeconds: TimeInterval = 0

    private var graceUntil: TimeInterval = 0
    private var stallStart: TimeInterval?
    private var isCurrentStallCounted = false
    private var lastPosition: Double?
    private var lastSampleTime: TimeInterval?

    init(startingAt time: TimeInterval = 0) {
        graceUntil = time + Self.startGrace
    }

    /// Restarts the grace period, e.g. after a seek or when the stream is rebuilt.
    mutating func restartGrace(at time: TimeInterval, duration: TimeInterval = Self.seekGrace) {
        graceUntil = max(graceUntil, time + duration)
        stallStart = nil
        isCurrentStallCounted = false
    }

    /// Feeds one sample. Returns `true` when a new stall was counted.
    mutating func sample(
        at time: TimeInterval,
        position: Double,
        isBuffering: Bool,
        wantsToPlay: Bool,
        rate: Double
    ) -> Bool {
        defer {
            lastPosition = position
            lastSampleTime = time
        }

        if let lastPosition, let lastSampleTime {
            let expected = wantsToPlay ? (time - lastSampleTime) * max(rate, 0) : 0

            if abs(position - lastPosition - expected) > Self.seekThreshold {
                restartGrace(at: time)
                return false
            }
        }

        guard wantsToPlay, time >= graceUntil, let lastPosition else {
            stallStart = nil
            isCurrentStallCounted = false
            return false
        }

        let isStalled = isBuffering && abs(position - lastPosition) < 0.25

        guard isStalled else {
            stallStart = nil
            isCurrentStallCounted = false
            return false
        }

        if let lastSampleTime, stallStart != nil {
            totalStallSeconds += time - lastSampleTime
        }

        let start = stallStart ?? time
        stallStart = start

        if !isCurrentStallCounted, time - start >= Self.minimumStall {
            isCurrentStallCounted = true
            stallCount += 1
            return true
        }

        return false
    }
}
