//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

// Note: the other couch language features add their strings in their own file
//       as `extension L10n.CouchLanguages { ... }` or their own enum.
//       Do not declare another `enum CouchLanguages` in `L10n`.

extension L10n {

    /// Strings that explain the couch's audio and subtitle pick.
    ///
    /// `names` parameters are localized lists, e.g. "Sam and Lisa".
    /// `language` parameters are localized language names, e.g. "Dutch".
    enum CouchLanguages {

        // MARK: Audio

        /// "Dutch audio"
        static func audio(_ language: String) -> String {
            "\(language) audio"
        }

        static let originalAudio = "Original audio"

        /// "Original audio (English)"
        static func originalAudioIn(_ language: String) -> String {
            "Original audio (\(language))"
        }

        /// The user picked an audio track in an unknown language.
        static let chosenAudio = "Chosen audio"

        // MARK: Subtitles

        static let noSubtitles = "no subtitles"

        /// "Dutch subtitles"
        static func subtitles(_ language: String) -> String {
            "\(language) subtitles"
        }

        static let forcedSubtitlesOnly = "forced subtitles only"

        /// The user picked the subtitle track.
        static let chosenSubtitles = "chosen subtitles"

        // MARK: Reasons

        /// "Tuur is on the couch"
        static func isOnTheCouch(_ name: String) -> String {
            "\(name) is on the couch"
        }

        /// "Tuur and Mia are on the couch"
        static func areOnTheCouch(_ names: String) -> String {
            "\(names) are on the couch"
        }

        /// "no Dutch audio for Tuur"
        static func noAudio(language: String, names: String) -> String {
            "no \(language) audio for \(names)"
        }

        /// "everyone understands Dutch"
        static func everyoneUnderstands(_ language: String) -> String {
            "everyone understands \(language)"
        }

        /// "for Sam and Lisa"
        static func neededBy(_ names: String) -> String {
            "for \(names)"
        }

        /// "Sam always wants subtitles"
        static func alwaysWantsSubtitles(_ name: String) -> String {
            "\(name) always wants subtitles"
        }

        /// "Sam and Lisa always want subtitles"
        static func alwaysWantSubtitles(_ names: String) -> String {
            "\(names) always want subtitles"
        }

        /// "Lisa doesn't read Dutch"
        static func doesNotRead(_ name: String, language: String) -> String {
            "\(name) doesn't read \(language)"
        }

        /// "Lisa and Mia don't read Dutch"
        static func doNotRead(_ names: String, language: String) -> String {
            "\(names) don't read \(language)"
        }

        /// "no subtitles Sam can read"
        static func noSubtitlesReadableBy(_ name: String) -> String {
            "no subtitles \(name) can read"
        }

        /// "no subtitles Sam and Lisa can all read"
        static func noSubtitlesReadableByAll(_ names: String) -> String {
            "no subtitles \(names) can all read"
        }

        // MARK: Summary

        /// "Dutch audio · no subtitles"
        static func summary(audio: String, subtitles: String) -> String {
            "\(audio) · \(subtitles)"
        }

        /// "Dutch audio · no subtitles — Tuur is on the couch"
        static func summary(audio: String, subtitles: String, reason: String) -> String {
            "\(audio) · \(subtitles) — \(reason)"
        }
    }
}
