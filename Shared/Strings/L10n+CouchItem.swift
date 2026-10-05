//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

extension L10n {

    /// Strings for the item page on a group couch: played state for everyone,
    /// whose resume point to start from, and the couch line under the buttons.
    ///
    /// `names` parameters are localized lists, e.g. "Sam, Lisa and Tuur".
    enum CouchItem {

        // MARK: Played

        static let markWatchedForEveryone = "Mark watched for everyone"
        static let markUnwatchedForEveryone = "Mark unwatched for everyone"

        /// Title of the dialog that asks whose watched state to clear.
        static let markUnwatchedFor = "Mark unwatched for…"

        static let everyoneOnTheCouch = "Everyone on the couch"

        /// "Just Tuur"
        static func just(_ name: String) -> String {
            "Just \(name)"
        }

        /// "Marked watched for Sam, Lisa and Tuur"
        static func markedWatched(_ names: String) -> String {
            "Marked watched for \(names)"
        }

        /// "Marked unwatched for Sam, Lisa and Tuur"
        static func markedUnwatched(_ names: String) -> String {
            "Marked unwatched for \(names)"
        }

        /// "Couldn't update Lisa"
        static func couldNotUpdate(_ names: String) -> String {
            "Couldn't update \(names)"
        }

        /// "Couldn't update Lisa: sign in again"
        static func couldNotUpdateSignIn(_ names: String) -> String {
            "Couldn't update \(names): sign in again"
        }

        /// "Marked watched for Sam. Couldn't update Lisa"
        static func twoSentences(_ first: String, _ second: String) -> String {
            "\(first). \(second)"
        }

        // MARK: Resume

        /// "Sam is at 1:10:05"
        static func isAt(_ name: String, time: String) -> String {
            "\(name) is at \(time)"
        }

        /// "Lisa and Tuur are at 42:10"
        static func areAt(_ names: String, time: String) -> String {
            "\(names) are at \(time)"
        }

        /// Title of the dialog that asks whose resume point to start from.
        static let whereToStart = "Where should we start?"

        /// "Resume from 42:10 (Lisa, Tuur)"
        static func resumeFrom(_ time: String, names: String) -> String {
            "Resume from \(time) (\(names))"
        }

        static let startOver = "Start over"

        // MARK: Couch line

        /// Accessibility hint of the couch line when it opens the audio and subtitle pickers.
        static let changeTracksHint = "Choose audio and subtitles"
    }
}
