//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// The audio sync fix for one file: one or two reference points.
///
/// Offsets use the player's convention (`MediaPlayerManager.audioOffset`, libVLC and mpv
/// audio delay): a positive offset plays the sound later, a negative offset plays it earlier.
///
/// - One point: a constant offset.
/// - Two points: a linear model `offset(t) = a + b·t` through both points, for sound that
///   drifts (a stretched or compressed audio track).
///
/// Foundation only: this file has no app dependencies.
struct AVSyncCorrection: Equatable, Sendable {

    struct Point: Equatable, Sendable {

        /// Position in the file, in seconds.
        var seconds: Double
        /// The audio offset that is right at `seconds`, in milliseconds.
        var offsetMilliseconds: Double
    }

    /// One or two points, sorted by time.
    private(set) var points: [Point]

    /// Two points must be at least this far apart (10 minutes) to describe drift.
    static let minimumPointSpacing: Double = 10 * 60
    /// Offsets are kept within this range, also when extrapolating drift.
    static let maximumOffsetMilliseconds: Double = 10000

    init?(points: [Point]) {
        let validPoints = points
            .filter { $0.seconds.isFinite && $0.offsetMilliseconds.isFinite && $0.seconds >= 0 }
            .sorted { $0.seconds < $1.seconds }
        let points = Array(validPoints.prefix(2))

        guard !points.isEmpty else { return nil }

        let isTooClose = points.count == 2 && points[1].seconds - points[0].seconds < Self.minimumPointSpacing

        // Too close together for drift: the later point wins
        self.points = isTooClose ? Array(points.suffix(1)) : points
    }

    init(constantOffsetMilliseconds offset: Double, at seconds: Double) {
        self.points = [Point(seconds: max(0, seconds), offsetMilliseconds: offset)]
    }

    var hasDrift: Bool {
        points.count == 2
    }

    /// Change of the offset per hour of playback, in milliseconds. `nil` for a constant offset.
    var driftMillisecondsPerHour: Double? {
        guard let slope else { return nil }

        return slope * 3600
    }

    private var slope: Double? {
        guard points.count == 2, let first = points.first, let last = points.last else { return nil }

        let span = last.seconds - first.seconds
        guard span > 0 else { return nil }

        return (last.offsetMilliseconds - first.offsetMilliseconds) / span
    }

    /// The offset to apply at `seconds`, in milliseconds.
    func offsetMilliseconds(at seconds: Double) -> Double {
        guard let first = points.first else { return 0 }

        let offset = first.offsetMilliseconds + (slope ?? 0) * (seconds - first.seconds)

        return min(max(offset, -Self.maximumOffsetMilliseconds), Self.maximumOffsetMilliseconds)
    }

    /// Whether a point at `seconds` would become a second point (for drift) instead of replacing the first.
    func addsSecondPoint(at seconds: Double) -> Bool {
        guard points.count == 1, let first = points.first else { return false }

        return abs(seconds - first.seconds) >= Self.minimumPointSpacing
    }

    /// The correction after fixing the sync again at `point.seconds`.
    ///
    /// - One point, far enough away: the new point becomes the second point (drift).
    /// - One point, too close: the new point replaces it.
    /// - Two points: the new point replaces the closer one. If the two are then too
    ///   close, only the new point is kept.
    func adding(_ point: Point) -> AVSyncCorrection {
        let newPoints = points.count < 2
            ? (addsSecondPoint(at: point.seconds) ? points + [point] : [point])
            : replacingClosestPoint(with: point)

        return AVSyncCorrection(points: newPoints) ?? AVSyncCorrection(
            constantOffsetMilliseconds: point.offsetMilliseconds,
            at: point.seconds
        )
    }

    private func replacingClosestPoint(with point: Point) -> [Point] {
        var closest = 0
        for index in points.indices where abs(points[index].seconds - point.seconds) < abs(points[closest].seconds - point.seconds) {
            closest = index
        }

        var newPoints = points
        newPoints[closest] = point

        let remaining = newPoints[closest == 0 ? 1 : 0]
        guard abs(remaining.seconds - point.seconds) >= Self.minimumPointSpacing else { return [point] }

        return newPoints
    }

    // MARK: - Storage

    /// Format version, the first field of the stored string.
    static let formatVersion = "1"

    /// Compact storage string: `1;<seconds·1000>:<offset ms>[;<seconds·1000>:<offset ms>]`.
    ///
    /// For example `1;1520400:-120;5320000:-180` is −120 ms at 25:20 and −180 ms at 1:28:40.
    var encoded: String {
        let fields = points.map { point in
            "\(Int64((point.seconds * 1000).rounded())):\(Int64(point.offsetMilliseconds.rounded()))"
        }

        return ([Self.formatVersion] + fields).joined(separator: ";")
    }

    init?(encoded: String) {
        let fields = encoded.split(separator: ";").map(String.init)

        guard fields.first == Self.formatVersion else { return nil }

        let points = fields.dropFirst().compactMap { field -> Point? in
            let parts = field.split(separator: ":")
            guard parts.count == 2,
                  let milliseconds = Double(parts[0]),
                  let offset = Double(parts[1])
            else { return nil }

            return Point(seconds: milliseconds / 1000, offsetMilliseconds: offset)
        }

        self.init(points: points)
    }
}

/// How far the sound is from the picture, as the sync studio explains it.
///
/// `soundLateness` is the opposite of the player offset: sound that comes 120 ms after the
/// picture (lateness +120 ms) is fixed by playing it 120 ms earlier (offset −120 ms).
enum AVSyncDirection: Equatable {

    case inSync
    case soundLate(milliseconds: Int)
    case soundEarly(milliseconds: Int)

    /// Offsets closer to zero than this read as in sync.
    static let inSyncThreshold = 0.5

    init(offsetMilliseconds offset: Double) {
        let lateness = -offset

        self = if abs(lateness) < Self.inSyncThreshold {
            .inSync
        } else if lateness > 0 {
            .soundLate(milliseconds: Int(lateness.rounded()))
        } else {
            .soundEarly(milliseconds: Int((-lateness).rounded()))
        }
    }
}
