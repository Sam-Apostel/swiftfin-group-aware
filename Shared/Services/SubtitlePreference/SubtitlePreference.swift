//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

/// The subtitle choice a user last made in the player: off, or on with a language and flavour.
struct SubtitlePreference: Hashable, Storable {

    enum Flavour: String, Codable, Hashable {
        /// Full dialogue.
        case regular
        /// Only foreign or hard-to-hear lines.
        case forced
        /// SDH / closed captions: dialogue plus sounds.
        case hearingImpaired
    }

    var isEnabled: Bool
    /// ISO 639-2 code, lowercased. `nil` when the chosen stream had no language.
    var language: String?
    var flavour: Flavour

    static let off = SubtitlePreference(isEnabled: false, language: nil, flavour: .regular)

    init(isEnabled: Bool, language: String?, flavour: Flavour) {
        self.isEnabled = isEnabled
        self.language = language
        self.flavour = flavour
    }

    /// An "on" preference matching the given subtitle stream.
    init(stream: MediaStream) {
        self.isEnabled = true
        self.language = Self.normalizedLanguage(stream.language)
        self.flavour = Self.flavour(of: stream)
    }

    // MARK: - Stream helpers

    static func normalizedLanguage(_ language: String?) -> String? {
        guard let language = language?.trimmingCharacters(in: .whitespaces).lowercased(),
              language.isNotEmpty,
              language != "und"
        else { return nil }

        return language
    }

    /// Reads the flavour from the stream's flags, falling back to "Forced" / "SDH" / "CC" in its title.
    static func flavour(of stream: MediaStream) -> Flavour {
        let titleWords = Set(
            (stream.title ?? "")
                .uppercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
        )

        if stream.isForced == true || titleWords.contains("FORCED") {
            return .forced
        }

        if stream.isHearingImpaired == true || titleWords.contains("SDH") || titleWords.contains("CC") {
            return .hearingImpaired
        }

        return .regular
    }

    // MARK: - Matching

    /// The stream index this preference picks from `streams`.
    ///
    /// - Returns: `-1` when subtitles are off, the best matching stream's index,
    ///   or `nil` when nothing matches and the caller should keep its default.
    func preferredIndex(in streams: [MediaStream]) -> Int? {
        guard isEnabled else { return -1 }

        let candidates = streams.filter { stream in
            guard stream.index != nil,
                  Self.normalizedLanguage(stream.language) == language
            else { return false }

            // Forced subtitles only cover some lines, so never swap them for full ones or the other way around.
            return (Self.flavour(of: stream) == .forced) == (flavour == .forced)
        }

        // Prefer the exact flavour, then text over image subtitles (image subtitles force the server to burn them in).
        let best = candidates.max { lhs, rhs in
            rank(of: lhs) < rank(of: rhs)
        }

        return best?.index
    }

    private func rank(of stream: MediaStream) -> Int {
        var rank = 0

        if Self.flavour(of: stream) == flavour {
            rank += 2
        }

        if stream.isTextSubtitleStream == true {
            rank += 1
        }

        return rank
    }
}
