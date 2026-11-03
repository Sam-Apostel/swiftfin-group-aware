//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// English strings for the sync studio (fixing audio that is out of sync with the picture).
extension L10n {

    enum AVSync {

        // MARK: - Entry

        static let fixAudioSync = "Fix audio sync"

        // MARK: - Direction

        static let inSync = "Sound and picture line up"
        static let noShift = "nothing shifted"
        static let picture = "Picture"
        static let sound = "Sound"

        static func soundLate(_ milliseconds: Int) -> String {
            "Sound is \(milliseconds) ms late"
        }

        static func soundEarly(_ milliseconds: Int) -> String {
            "Sound is \(milliseconds) ms early"
        }

        static func playingEarlier(_ milliseconds: Int) -> String {
            "playing it \(milliseconds) ms earlier"
        }

        static func playingLater(_ milliseconds: Int) -> String {
            "playing it \(milliseconds) ms later"
        }

        static func milliseconds(_ milliseconds: Int) -> String {
            "\(milliseconds) ms"
        }

        // MARK: - Guidance

        static let hintTV =
            "Swipe to move the picture or slide the sound under the line. Click left or right for one frame, play/pause to check."
        static let hintPhone = "Find a frame with a sound, then drag the sound under the line."
        static let listening = "Listening…"
        static let waveformFailed = "Couldn't fetch the sound. You can still slide it and check by ear."

        // MARK: - Actions

        static let previousFrame = "Previous frame"
        static let nextFrame = "Next frame"
        static let check = "Check"
        static let stop = "Stop"
        static let save = "Save"
        static let saveSecondPoint = "Save second point"

        // MARK: - Saved fix

        static let savedForFile = "Sync saved for this file"
        static let savedWithDrift = "Sync saved for this file, with drift"
        static let secondPointReady = "Saving here adds a second point, for sound that drifts."
        static let secondPointTooClose = "For drift, a second point needs 10 min between them."

        // MARK: - Toasts

        static let savedToast = "Sync saved for this file"
        static let savedFirstToast = "Sync saved. Drifts later on? Fix it again further in."
        static let notSavedToast = "Fixed for now, but couldn't save it"
        static let resetToast = "Sync reset for this file"
    }
}
