//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

extension L10n {

    /// Strings of the Languages section in Couch settings, the person page and the language list.
    ///
    /// `name` parameters are a person's name, e.g. "Lisa".
    /// `language` / `languages` parameters are localized language names, e.g. "Dutch" or "English, French".
    enum CouchLanguageSettings {

        // MARK: Couch settings section

        static let languages = "Languages"
        static let pickLanguagesForTheCouch = "Pick languages for the couch"
        static let pickLanguagesFooter =
            "When several people watch, Couchfin first picks audio that people who don't read subtitles understand. It keeps the original audio when everyone follows it, and turns on subtitles in a language everyone who needs them can read. Watching alone uses your Jellyfin settings, as before."

        /// "No languages set — Couchfin won't adjust for Lisa"
        static func noLanguagesSet(_ name: String) -> String {
            "No languages set — Couchfin won't adjust for \(name)"
        }

        // MARK: Row summary

        /// "doesn't read subtitles"
        static let doesNotReadSubtitlesShort = "doesn't read subtitles"

        /// "Dutch subtitles (Smart)"
        static func subtitles(_ language: String, mode: String) -> String {
            "\(language) subtitles (\(mode))"
        }

        /// "subtitles (Always)"
        static func subtitlesWithoutLanguage(mode: String) -> String {
            "subtitles (\(mode))"
        }

        /// "also understands English, French"
        static func alsoUnderstandsSummary(_ languages: String) -> String {
            "also understands \(languages)"
        }

        // MARK: Person page

        static let jellyfinSettings = "Jellyfin settings"
        static let audioLanguage = "Audio language"
        static let subtitleLanguage = "Subtitle language"
        static let noneMeansOriginalAudio = "An audio language of None means the original audio."

        /// "Also used when Lisa watches alone, in every Jellyfin app."
        static func alsoUsedWhenWatchingAlone(_ name: String) -> String {
            "Also used when \(name) watches alone, in every Jellyfin app."
        }

        /// "Tuur's account can't change these settings, so they're saved for the couch only."
        static func savedForCouchOnly(_ name: String) -> String {
            "\(name)'s account can't change these settings, so they're saved for the couch only."
        }

        static let onTheCouch = "On the couch"
        static let alsoUnderstands = "Also understands"
        static let readsSubtitles = "Reads subtitles"
        static let alsoReads = "Also reads"

        /// "Only Couchfin uses these, to pick tracks when Lisa watches with others."
        static func onTheCouchFooter(_ name: String) -> String {
            "Only Couchfin uses these, to pick tracks when \(name) watches with others."
        }

        static let whatCouchfinAssumes = "What Couchfin assumes"
        static let understands = "Understands"
        static let reads = "Reads"
        static let doesNotReadSubtitles = "Doesn't read subtitles"
        static let notSet = "Not set"

        /// "Set an audio language so Couchfin can pick for Tuur"
        static func setAudioLanguageHint(_ name: String) -> String {
            "Set an audio language so Couchfin can pick for \(name)"
        }

        static let personNotFound = "This person isn't on this device anymore"

        // MARK: Language list

        static let selected = "Selected"
        static let common = "Common"
        static let allLanguages = "All languages"
        static let languagesUnavailable = "Couldn't load languages"
        static let languagesUnavailableDescription = "Check the connection to your server and try again."
    }
}
