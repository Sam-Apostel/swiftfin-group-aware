//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// Turns a short WAV clip into a loudness envelope for the sync studio.
///
/// Foundation only and free of side effects, so it can be tested on its own.
enum AVSyncWaveform {

    struct PCMFormat: Equatable, Sendable {

        let sampleRate: Int
        let channels: Int
        let bitsPerSample: Int
    }

    /// Loudness over time, one level per bucket.
    struct Envelope: Equatable, Sendable {

        /// Position in the file of the start of the first bucket, in seconds.
        let startSeconds: Double
        /// Length of one bucket, in seconds.
        let bucketSeconds: Double
        /// Levels from 0 (silence) to 1 (the loudest bucket in the clip).
        let levels: [Float]

        var endSeconds: Double {
            startSeconds + Double(levels.count) * bucketSeconds
        }

        /// The level of the bucket at `seconds`, or `nil` outside the clip.
        func level(at seconds: Double) -> Float? {
            guard bucketSeconds > 0, seconds >= startSeconds else { return nil }

            let index = Int((seconds - startSeconds) / bucketSeconds)
            guard index >= 0, index < levels.count else { return nil }

            return levels[index]
        }
    }

    /// Request settings: mono 16-bit PCM at 8 kHz is plenty to see a clap or a door.
    static let sampleRate = 8000
    static let channels = 1
    /// 5 ms buckets.
    static let bucketSeconds = 0.005

    /// How many bytes to read for `seconds` of audio, with room for the header.
    static func byteCount(forSeconds seconds: Double, sampleRate: Int = sampleRate, channels: Int = channels) -> Int {
        let headerAllowance = 4096
        return headerAllowance + Int(seconds * Double(sampleRate * channels * 2))
    }

    // MARK: - WAV

    /// Finds the format and the sample bytes of a 16-bit PCM WAV file.
    ///
    /// A streamed WAV often has an unknown length (0 or 0xFFFFFFFF in the size fields),
    /// and the clip is cut off anyway, so the data chunk runs to the end of `data`.
    static func parseWAV(_ data: Data) -> (format: PCMFormat, samples: [UInt8])? {
        let bytes = [UInt8](data)

        guard bytes.count >= 12,
              let riff = fourCC(bytes, at: 0),
              riff == "RIFF" || riff == "RF64",
              fourCC(bytes, at: 8) == "WAVE"
        else { return nil }

        var format: PCMFormat?
        var offset = 12

        while offset + 8 <= bytes.count {
            guard let id = fourCC(bytes, at: offset), let size = uint32(bytes, at: offset + 4) else { return nil }

            let bodyStart = offset + 8

            if id == "fmt " {
                // Format 1 is PCM, 0xFFFE is WAVE_FORMAT_EXTENSIBLE (PCM in practice)
                guard let audioFormat = uint16(bytes, at: bodyStart),
                      let channels = uint16(bytes, at: bodyStart + 2),
                      let sampleRate = uint32(bytes, at: bodyStart + 4),
                      let bitsPerSample = uint16(bytes, at: bodyStart + 14),
                      audioFormat == 1 || audioFormat == 0xFFFE,
                      bitsPerSample == 16,
                      channels > 0,
                      sampleRate > 0
                else { return nil }

                format = PCMFormat(
                    sampleRate: Int(sampleRate),
                    channels: Int(channels),
                    bitsPerSample: Int(bitsPerSample)
                )
            } else if id == "data" {
                guard let format else { return nil }

                let isUnknownSize = size == 0 || size == UInt32.max
                let end = isUnknownSize ? bytes.count : min(bytes.count, bodyStart + Int(size))
                guard end > bodyStart else { return nil }

                return (format, Array(bytes[bodyStart ..< end]))
            }

            guard size != UInt32.max else { return nil }

            // Chunks are padded to an even size
            offset = bodyStart + Int(size) + Int(size & 1)
        }

        return nil
    }

    // MARK: - Envelope

    /// RMS loudness per bucket, normalised to the loudest bucket and lifted with a square root
    /// so quiet sounds stay visible next to loud ones.
    static func envelope(
        samples: [UInt8],
        format: PCMFormat,
        startSeconds: Double,
        bucketSeconds: Double = bucketSeconds
    ) -> Envelope? {
        guard format.bitsPerSample == 16, format.channels > 0, format.sampleRate > 0, bucketSeconds > 0 else { return nil }

        let frameSize = format.channels * 2
        let frameCount = samples.count / frameSize
        let framesPerBucket = max(1, Int((Double(format.sampleRate) * bucketSeconds).rounded()))
        let bucketCount = frameCount / framesPerBucket

        guard bucketCount > 0 else { return nil }

        var rmsLevels: [Double] = []
        rmsLevels.reserveCapacity(bucketCount)

        for bucket in 0 ..< bucketCount {
            var sumOfSquares: Double = 0
            let firstFrame = bucket * framesPerBucket

            for frame in firstFrame ..< firstFrame + framesPerBucket {
                for channel in 0 ..< format.channels {
                    let index = frame * frameSize + channel * 2
                    let value = Int16(bitPattern: UInt16(samples[index]) | (UInt16(samples[index + 1]) << 8))
                    let normalised = Double(value) / 32768
                    sumOfSquares += normalised * normalised
                }
            }

            rmsLevels.append((sumOfSquares / Double(framesPerBucket * format.channels)).squareRoot())
        }

        // Keep near-silent clips flat instead of blowing up the noise floor
        let loudest = max(rmsLevels.max() ?? 0, 0.02)
        let levels = rmsLevels.map { Float(min(1, ($0 / loudest).squareRoot())) }

        return Envelope(
            startSeconds: startSeconds,
            bucketSeconds: Double(framesPerBucket) / Double(format.sampleRate),
            levels: levels
        )
    }

    // MARK: - Bytes

    private static func fourCC(_ bytes: [UInt8], at offset: Int) -> String? {
        guard offset >= 0, offset + 4 <= bytes.count else { return nil }

        return String(bytes: bytes[offset ..< offset + 4], encoding: .ascii)
    }

    private static func uint16(_ bytes: [UInt8], at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= bytes.count else { return nil }

        return UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func uint32(_ bytes: [UInt8], at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= bytes.count else { return nil }

        return UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }
}
