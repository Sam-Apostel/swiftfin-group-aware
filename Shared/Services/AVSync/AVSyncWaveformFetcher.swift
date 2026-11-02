//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

/// Fetches a few seconds of a file's sound for the sync studio.
///
/// Asks the server for an audio-only transcode (`/Audio/{id}/stream.wav`, mono 16-bit PCM at 8 kHz)
/// starting at the requested position, reads only as many bytes as needed and then hangs up,
/// which ends the server's transcode.
enum AVSyncWaveformFetcher {

    /// The streaming URL. The audio endpoint accepts video items: it builds an audio-only job.
    static func url(
        itemID: String,
        mediaSourceID: String?,
        audioStreamIndex: Int?,
        startSeconds: Double,
        client: JellyfinClient
    ) -> URL? {
        var parameters = Paths.GetAudioStreamByContainerParameters()
        parameters.isStatic = false
        parameters.mediaSourceID = mediaSourceID ?? itemID
        // Own device and play session, so this job never replaces the video's transcode
        parameters.deviceID = "\(client.configuration.deviceID)-avsync"
        parameters.playSessionID = UUID().uuidString
        parameters.audioCodec = "pcm_s16le"
        parameters.audioSampleRate = AVSyncWaveform.sampleRate
        parameters.audioChannels = AVSyncWaveform.channels
        parameters.maxAudioChannels = AVSyncWaveform.channels
        parameters.enableAutoStreamCopy = false
        parameters.allowAudioStreamCopy = false
        parameters.startTimeTicks = Duration.seconds(max(0, startSeconds)).ticks

        if let audioStreamIndex, audioStreamIndex >= 0 {
            parameters.audioStreamIndex = audioStreamIndex
        }

        let request = Paths.getAudioStreamByContainer(
            itemID: itemID,
            container: "wav",
            parameters: parameters
        )

        return client.url(with: request, queryAPIKey: true)
    }

    /// The loudness envelope of `durationSeconds` of sound from `startSeconds` on.
    static func fetchEnvelope(
        itemID: String,
        mediaSourceID: String?,
        audioStreamIndex: Int?,
        startSeconds: Double,
        durationSeconds: Double,
        client: JellyfinClient
    ) async throws -> AVSyncWaveform.Envelope {
        let startSeconds = max(0, startSeconds)

        guard let url = url(
            itemID: itemID,
            mediaSourceID: mediaSourceID,
            audioStreamIndex: audioStreamIndex,
            startSeconds: startSeconds,
            client: client
        ) else {
            throw ErrorMessage("Unable to make the audio clip URL")
        }

        let byteLimit = AVSyncWaveform.byteCount(forSeconds: durationSeconds)
        let bytes = try await readPrefix(of: url, byteLimit: byteLimit)

        guard let wav = AVSyncWaveform.parseWAV(Data(bytes)),
              let envelope = AVSyncWaveform.envelope(
                  samples: wav.samples,
                  format: wav.format,
                  startSeconds: startSeconds
              )
        else {
            throw ErrorMessage("The audio clip could not be read")
        }

        return envelope
    }

    /// Reads up to `byteLimit` bytes, then cancels the request. A shorter response (the end of
    /// the file) is returned as is.
    private static func readPrefix(of url: URL, byteLimit: Int) async throws -> [UInt8] {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20

        let (stream, response) = try await URLSession.shared.bytes(for: request)
        defer { stream.task.cancel() }

        if let response = response as? HTTPURLResponse, !(200 ..< 300).contains(response.statusCode) {
            throw ErrorMessage("The server could not make an audio clip (\(response.statusCode))")
        }

        var buffer: [UInt8] = []
        buffer.reserveCapacity(byteLimit)

        for try await byte in stream {
            buffer.append(byte)

            if buffer.count >= byteLimit {
                break
            }
        }

        return buffer
    }
}
