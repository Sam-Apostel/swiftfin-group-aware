//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// English strings for remembered subtitle choices.
/// Kept out of the generated `Strings.swift` to avoid merge conflicts.
extension L10n {

    enum RememberedSubtitles {

        static let title = "Subtitles"
        static let off = "Off"
        static let forced = "forced"
        static let sdh = "SDH"
        static let unknownLanguage = "Unknown language"
        static let notYet = "Nothing remembered yet"
        static let forget = "Forget"
        static let footer =
            "Turn subtitles on or off while watching and Couchfin keeps that choice for everything you play next, on all your devices."

        /// "English · remembered"
        static func remembered(_ choice: String) -> String {
            "\(choice) · remembered"
        }

        /// "English (SDH)"
        static func languageWithFlavour(_ language: String, _ flavour: String) -> String {
            "\(language) (\(flavour))"
        }
    }
}
