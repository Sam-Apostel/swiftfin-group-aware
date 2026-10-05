//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

// Foundation only: this file is type-checked and unit-tested on Linux.

// MARK: - Language codes

/// Normalises the language codes used by Jellyfin cultures, user preferences and stream tags.
///
/// Jellyfin cultures use ISO 639-2/B codes (`dut`), while stream tags written by ffprobe or
/// mkvmerge may use T codes (`nld`), two-letter codes (`nl`) or regional tags (`nl-BE`).
/// Every code is compared in its canonical form: lowercased ISO 639-2/B.
enum CouchLanguageCode {

    /// The canonical form of a language code: lowercased ISO 639-2/B.
    ///
    /// Accepts two-letter (ISO 639-1), T and B codes, regional tags like `nl-BE` or `pt_BR`,
    /// and a few English language names. Unknown codes that look like a code are kept as is.
    ///
    /// - Returns: `nil` for `und`, `zxx`, `mul`, other "unknown" markers and empty strings.
    static func canonical(_ code: String?) -> String? {
        guard let code else { return nil }

        var value = code
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if let separator = value.firstIndex(where: { $0 == "-" || $0 == "_" }) {
            value = String(value[..<separator])
        }

        guard value.isEmpty == false, unknownCodes.contains(value) == false else { return nil }

        switch value.count {
        case 2:
            return twoLetterToBibliographic[value] ?? value
        case 3:
            return aliases[value] ?? terminologyToBibliographic[value] ?? value
        default:
            return namesToBibliographic[value] ?? value
        }
    }

    /// The two-letter ISO 639-1 code of a language, for display (`"dut"` → `"nl"`).
    ///
    /// - Returns: `nil` when the language is not in the table.
    static func twoLetter(_ code: String?) -> String? {
        guard let canonical = canonical(code) else { return nil }

        return bibliographicToTwoLetter[canonical]
    }

    /// Canonical, de-duplicated codes from a comma separated list, in their original order.
    ///
    /// `"dut, nld,eng"` → `["dut", "eng"]`.
    static func list(from csv: String?) -> [String] {
        guard let csv else { return [] }

        let parts = csv.split { $0 == "," || $0 == ";" || $0 == "|" }

        return unique(parts.map { String($0) })
    }

    /// A comma separated list of canonical, de-duplicated codes.
    static func csv(from codes: [String]) -> String {
        unique(codes).joined(separator: ",")
    }

    /// Canonical, de-duplicated codes in their original order. Unknown codes are dropped.
    static func unique(_ codes: [String?]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []

        for code in codes {
            guard let canonical = canonical(code), seen.insert(canonical).inserted else { continue }

            result.append(canonical)
        }

        return result
    }

    // MARK: Tables

    /// Codes that mean "no known language".
    private static let unknownCodes: Set<String> = [
        "und", "zxx", "mul", "mis", "unknown", "undetermined", "undefined", "none", "null",
    ]

    /// The 20 ISO 639-2 languages whose terminology (T) code differs from the bibliographic (B) code.
    private static let terminologyToBibliographic: [String: String] = [
        "bod": "tib", // Tibetan
        "ces": "cze", // Czech
        "cym": "wel", // Welsh
        "deu": "ger", // German
        "ell": "gre", // Greek
        "eus": "baq", // Basque
        "fas": "per", // Persian
        "fra": "fre", // French
        "hye": "arm", // Armenian
        "isl": "ice", // Icelandic
        "kat": "geo", // Georgian
        "mkd": "mac", // Macedonian
        "mri": "mao", // Maori
        "msa": "may", // Malay
        "mya": "bur", // Burmese
        "nld": "dut", // Dutch
        "ron": "rum", // Romanian
        "slk": "slo", // Slovak
        "sqi": "alb", // Albanian
        "zho": "chi", // Chinese
    ]

    /// Three-letter codes that are treated as the same language as another code.
    private static let aliases: [String: String] = [
        "cmn": "chi", // Mandarin
        "mol": "rum", // Moldavian
        "nno": "nor", // Norwegian Nynorsk
        "nob": "nor", // Norwegian Bokmål
        "scc": "srp", // Serbian (deprecated B code)
        "scr": "hrv", // Croatian (deprecated B code)
    ]

    /// ISO 639-1 → ISO 639-2/B. The first pair of a B code is its display code.
    private static let twoLetterPairs: [(String, String)] = [
        ("af", "afr"), ("am", "amh"), ("ar", "ara"), ("ay", "aym"), ("az", "aze"),
        ("be", "bel"), ("bg", "bul"), ("bn", "ben"), ("bo", "tib"), ("br", "bre"),
        ("bs", "bos"), ("ca", "cat"), ("co", "cos"), ("cs", "cze"), ("cy", "wel"),
        ("da", "dan"), ("de", "ger"), ("el", "gre"), ("en", "eng"), ("eo", "epo"),
        ("es", "spa"), ("et", "est"), ("eu", "baq"), ("fa", "per"), ("fi", "fin"),
        ("fj", "fij"), ("fo", "fao"), ("fr", "fre"), ("fy", "fry"), ("ga", "gle"),
        ("gd", "gla"), ("gl", "glg"), ("gn", "grn"), ("gu", "guj"), ("ha", "hau"),
        ("he", "heb"), ("hi", "hin"), ("hr", "hrv"), ("ht", "hat"), ("hu", "hun"),
        ("hy", "arm"), ("id", "ind"), ("ig", "ibo"), ("is", "ice"), ("it", "ita"),
        ("ja", "jpn"), ("jv", "jav"), ("ka", "geo"), ("kk", "kaz"), ("km", "khm"),
        ("kn", "kan"), ("ko", "kor"), ("ku", "kur"), ("ky", "kir"), ("la", "lat"),
        ("lb", "ltz"), ("lo", "lao"), ("lt", "lit"), ("lv", "lav"), ("mg", "mlg"),
        ("mi", "mao"), ("mk", "mac"), ("ml", "mal"), ("mn", "mon"), ("mr", "mar"),
        ("ms", "may"), ("mt", "mlt"), ("my", "bur"), ("ne", "nep"), ("nl", "dut"),
        ("no", "nor"), ("nb", "nor"), ("nn", "nor"), ("oc", "oci"), ("pa", "pan"),
        ("pl", "pol"), ("ps", "pus"), ("pt", "por"), ("qu", "que"), ("ro", "rum"),
        ("ru", "rus"), ("rw", "kin"), ("sd", "snd"), ("si", "sin"), ("sk", "slo"),
        ("sl", "slv"), ("sm", "smo"), ("sn", "sna"), ("so", "som"), ("sq", "alb"),
        ("sr", "srp"), ("st", "sot"), ("su", "sun"), ("sv", "swe"), ("sw", "swa"),
        ("ta", "tam"), ("te", "tel"), ("tg", "tgk"), ("th", "tha"), ("tk", "tuk"),
        ("tl", "tgl"), ("tn", "tsn"), ("to", "ton"), ("tr", "tur"), ("tt", "tat"),
        ("ug", "uig"), ("uk", "ukr"), ("ur", "urd"), ("uz", "uzb"), ("vi", "vie"),
        ("wo", "wol"), ("xh", "xho"), ("yi", "yid"), ("yo", "yor"), ("zh", "chi"),
        ("zu", "zul"),
        // Deprecated ISO 639-1 codes still found in older files
        ("iw", "heb"), ("in", "ind"), ("ji", "yid"),
    ]

    private static let twoLetterToBibliographic: [String: String] = Dictionary(
        twoLetterPairs,
        uniquingKeysWith: { first, _ in first }
    )

    private static let bibliographicToTwoLetter: [String: String] = Dictionary(
        twoLetterPairs.map { ($0.1, $0.0) },
        uniquingKeysWith: { first, _ in first }
    )

    /// English names that some files use instead of a code.
    private static let namesToBibliographic: [String: String] = [
        "arabic": "ara", "chinese": "chi", "danish": "dan", "dutch": "dut", "english": "eng",
        "finnish": "fin", "flemish": "dut", "french": "fre", "german": "ger", "greek": "gre",
        "hebrew": "heb", "hindi": "hin", "italian": "ita", "japanese": "jpn", "korean": "kor",
        "norwegian": "nor", "polish": "pol", "portuguese": "por", "russian": "rus", "spanish": "spa",
        "swedish": "swe", "turkish": "tur",
    ]
}

// MARK: - Subtitle mode

/// A person's subtitle mode, with the same raw values as `JellyfinAPI.SubtitlePlaybackMode`.
enum CouchSubtitleMode: String, Codable, Hashable, Sendable, CaseIterable {
    /// Subtitles when the audio is not in the person's language.
    case `default` = "Default"
    /// Always subtitles.
    case always = "Always"
    /// Only forced subtitles; on the couch this behaves like `default`.
    case onlyForced = "OnlyForced"
    /// Never subtitles.
    case none = "None"
    /// Subtitles only when the audio isn't in the subtitle language: the subtitle language is also understood.
    case smart = "Smart"
}

// MARK: - Profile

/// What one person on the couch understands and reads, derived from their Jellyfin
/// preferences plus the couch-only extras.
struct CouchLanguageProfile: Hashable, Sendable {

    let userID: String
    let name: String
    let isKid: Bool
    /// Lower is more restricted; kids are `-1`.
    let restrictionScore: Int
    /// Canonical; `nil` means original audio.
    let audioLanguage: String?
    /// Canonical.
    let subtitleLanguage: String?
    let subtitleMode: CouchSubtitleMode
    /// Canonical, ordered by preference, unique.
    let understands: [String]
    let readsSubtitles: Bool
    /// Canonical, ordered by preference, unique; `[]` when `!readsSubtitles`.
    let reads: [String]

    /// The person wants the original audio track.
    var prefersOriginalAudio: Bool {
        audioLanguage == nil
    }

    /// Without known languages a person never constrains the audio and only
    /// asks for subtitles when their mode is `.always`.
    var isFlexible: Bool {
        understands.isEmpty
    }

    /// Someone who needs audio in a language they understand, because they don't read subtitles.
    var isListener: Bool {
        !readsSubtitles && !understands.isEmpty
    }

    /// Applies the derivation rules, canonicalising every code:
    ///
    /// - `understands = [audioLanguage] + alsoUnderstands + (smart ? [subtitleLanguage] : [])`
    /// - `readsSubtitles = readsSubtitles ?? !isKid`
    /// - `reads = readsSubtitles ? [subtitleLanguage] + alsoReads + understands : []`
    init(
        userID: String,
        name: String,
        isKid: Bool,
        restrictionScore: Int,
        audioLanguagePreference: String?,
        subtitleLanguagePreference: String?,
        subtitleMode: CouchSubtitleMode,
        alsoUnderstands: [String],
        alsoReads: [String],
        readsSubtitles: Bool?
    ) {
        let audioLanguage = CouchLanguageCode.canonical(audioLanguagePreference)
        let subtitleLanguage = CouchLanguageCode.canonical(subtitleLanguagePreference)
        let smartLanguages: [String?] = subtitleMode == .smart ? [subtitleLanguage] : []
        let understands = CouchLanguageCode.unique([audioLanguage] + alsoUnderstands.map(\.self) + smartLanguages)
        let readsSubtitles = readsSubtitles ?? !isKid

        self.userID = userID
        self.name = name
        self.isKid = isKid
        self.restrictionScore = restrictionScore
        self.audioLanguage = audioLanguage
        self.subtitleLanguage = subtitleLanguage
        self.subtitleMode = subtitleMode
        self.understands = understands
        self.readsSubtitles = readsSubtitles
        self.reads = readsSubtitles
            ? CouchLanguageCode.unique([subtitleLanguage] + alsoReads.map(\.self) + understands.map(\.self))
            : []
    }
}

// MARK: - Stream candidate

/// An audio or subtitle track the rule may choose.
struct CouchStreamCandidate: Hashable, Sendable {

    /// The Jellyfin stream index.
    let index: Int
    /// Canonical; `nil` when unknown.
    let language: String?
    let isDefault: Bool
    let isForced: Bool
    /// Audio: a direct-playable codec. Subtitles: no burn-in needed.
    let isPlayableWithoutTranscode: Bool

    /// - Parameter language: any language code; it is canonicalised.
    init(
        index: Int,
        language: String?,
        isDefault: Bool = false,
        isForced: Bool = false,
        isPlayableWithoutTranscode: Bool = true
    ) {
        self.index = index
        self.language = CouchLanguageCode.canonical(language)
        self.isDefault = isDefault
        self.isForced = isForced
        self.isPlayableWithoutTranscode = isPlayableWithoutTranscode
    }
}

// MARK: - Decision

/// The audio and subtitle tracks chosen for the couch, and why.
struct CouchLanguageDecision: Hashable, Sendable {

    enum AudioReason: Hashable, Sendable {
        /// Audio that these listeners (people who don't read subtitles) understand.
        case listeners([String])
        /// The original track.
        case original
        /// Someone can't follow the original, and everyone understands this language.
        case everyoneUnderstands(String)
        /// The user picked the audio track.
        case userChoice
    }

    enum SubtitleReason: Hashable, Sendable {
        /// Nobody needs subtitles.
        case notNeeded
        /// Nobody needs subtitles, but the file has forced subtitles for the audio language.
        case forcedOnly
        /// These people don't understand the audio.
        case neededBy([String])
        /// Only people who always want subtitles turned them on.
        case alwaysOn([String])
        /// No language every needer reads: these needers can't read the chosen subtitles.
        case partial(missing: [String])
        /// These people need subtitles, but there are none in a language they read.
        case noSharedLanguage([String])
        /// The user picked the subtitle track.
        case userChoice
    }

    /// `nil` only when there is no audio candidate.
    let audioStreamIndex: Int?
    /// Canonical.
    let audioLanguage: String?
    /// `-1` turns subtitles off; `nil` keeps the user's explicit subtitle pick.
    let subtitleStreamIndex: Int?
    /// Canonical.
    let subtitleLanguage: String?
    let audioReason: AudioReason
    let subtitleReason: SubtitleReason
    /// Names of the listeners no audio track works for, in couch order.
    let unservedListeners: [String]
    /// The preferred language of each unserved listener (canonical, unique), for "no Dutch audio for Tuur".
    let unservedLanguages: [String]

    init(
        audioStreamIndex: Int?,
        audioLanguage: String?,
        subtitleStreamIndex: Int?,
        subtitleLanguage: String?,
        audioReason: AudioReason,
        subtitleReason: SubtitleReason,
        unservedListeners: [String],
        unservedLanguages: [String] = []
    ) {
        self.audioStreamIndex = audioStreamIndex
        self.audioLanguage = audioLanguage
        self.subtitleStreamIndex = subtitleStreamIndex
        self.subtitleLanguage = subtitleLanguage
        self.audioReason = audioReason
        self.subtitleReason = subtitleReason
        self.unservedListeners = unservedListeners
        self.unservedLanguages = unservedLanguages
    }
}

// MARK: - Rule

/// Picks the audio and subtitle tracks that work for everyone on the couch. Pure and deterministic.
///
/// **Audio** (skipped when the user picked a track), the first step that matches wins:
/// 1. **Listeners first.** People who don't read subtitles and have a known language (kids) get a track
///    they all understand: the language the most people understand, then the listeners' own order.
///    When no track works for all of them, the most restricted listeners (kids first, then
///    `restrictionScore`) are served and the others are reported as `unservedListeners`.
/// 2. **Original unless someone can't follow it.** When someone with known languages neither understands
///    the original language nor prefers original audio, and a track is understood by everyone with known
///    languages (unserved listeners excluded: no track works for them), that track plays.
/// 3. **Otherwise the original track:** the default-flagged track, else the first.
///
/// Audio in an unknown language counts as understood by everyone.
///
/// **Subtitles** (skipped when the user picked a track) are decided against the chosen audio language:
/// *needers* read subtitles, don't use mode `.none`, and either use `.always` or don't understand the audio.
/// Without needers a forced track in the audio language (or an unknown language) plays when one exists,
/// otherwise subtitles are off (`-1`). With needers, a full track in a language every needer reads
/// plays; else the language read by the most needers; else subtitles are off.
///
/// **Ties** between languages go to the lowest summed preference rank, then to the first person in couch order
/// (primary first) who ranks them differently. Among tracks in one language the original track wins its own
/// language; otherwise a track that plays without a transcode, then the default flag, then the lowest index.
enum CouchLanguageRule {

    /// - Parameters:
    ///   - profiles: everyone on the couch, in couch order (primary first).
    ///   - fixedAudioIndex: the user's explicit audio pick (reason `.userChoice`); subtitles are decided against it.
    ///   - decideSubtitles: `false` keeps the user's explicit subtitle pick: `subtitleStreamIndex` is `nil`,
    ///     reason `.userChoice`.
    static func decide(
        profiles: [CouchLanguageProfile],
        audio: [CouchStreamCandidate],
        subtitles: [CouchStreamCandidate],
        fixedAudioIndex: Int? = nil,
        decideSubtitles: Bool = true
    ) -> CouchLanguageDecision {

        let audioChoice = chooseAudio(
            profiles: profiles,
            audio: audio,
            fixedAudioIndex: fixedAudioIndex
        )

        guard decideSubtitles else {
            return CouchLanguageDecision(
                audioStreamIndex: audioChoice.index,
                audioLanguage: audioChoice.language,
                subtitleStreamIndex: nil,
                subtitleLanguage: nil,
                audioReason: audioChoice.reason,
                subtitleReason: .userChoice,
                unservedListeners: audioChoice.unservedListeners,
                unservedLanguages: audioChoice.unservedLanguages
            )
        }

        let subtitleChoice = chooseSubtitles(
            profiles: profiles,
            subtitles: subtitles,
            audioLanguage: audioChoice.language
        )

        return CouchLanguageDecision(
            audioStreamIndex: audioChoice.index,
            audioLanguage: audioChoice.language,
            subtitleStreamIndex: subtitleChoice.index,
            subtitleLanguage: subtitleChoice.language,
            audioReason: audioChoice.reason,
            subtitleReason: subtitleChoice.reason,
            unservedListeners: audioChoice.unservedListeners,
            unservedLanguages: audioChoice.unservedLanguages
        )
    }
}

// MARK: - Audio

extension CouchLanguageRule {

    private struct AudioChoice {
        let index: Int?
        let language: String?
        let reason: CouchLanguageDecision.AudioReason
        var unservedListeners: [String] = []
        var unservedLanguages: [String] = []
    }

    private static func chooseAudio(
        profiles: [CouchLanguageProfile],
        audio: [CouchStreamCandidate],
        fixedAudioIndex: Int?
    ) -> AudioChoice {

        if let fixedAudioIndex {
            let fixed = audio.first { $0.index == fixedAudioIndex }
            return AudioChoice(index: fixedAudioIndex, language: fixed?.language, reason: .userChoice)
        }

        let original = audio.first(where: \.isDefault) ?? audio.first
        let languages = trackLanguages(audio, original: original)
        let couchOrder = Dictionary(profiles.enumerated().map { ($1.userID, $0) }, uniquingKeysWith: { first, _ in first })

        // a. Listeners first: serve the most restricted listeners greedily.
        let listenersByRestriction = profiles
            .filter(\.isListener)
            .sorted { lhs, rhs in
                if lhs.isKid != rhs.isKid {
                    return lhs.isKid
                }
                if lhs.restrictionScore != rhs.restrictionScore {
                    return lhs.restrictionScore < rhs.restrictionScore
                }
                return (couchOrder[lhs.userID] ?? 0) < (couchOrder[rhs.userID] ?? 0)
            }

        var served: [CouchLanguageProfile] = []
        var unserved: [CouchLanguageProfile] = []

        // Untagged audio counts as understood by everyone: without any known language there is nothing to serve.
        for listener in listenersByRestriction where !languages.isEmpty {
            let candidateGroup = served + [listener]
            let isServable = languages.contains { language in
                candidateGroup.allSatisfy { $0.understands.contains(language) }
            }

            if isServable {
                served.append(listener)
            } else {
                unserved.append(listener)
            }
        }

        served.sort { (couchOrder[$0.userID] ?? 0) < (couchOrder[$1.userID] ?? 0) }
        unserved.sort { (couchOrder[$0.userID] ?? 0) < (couchOrder[$1.userID] ?? 0) }

        let unservedNames = unserved.map(\.name)
        let unservedLanguages = CouchLanguageCode.unique(unserved.map(\.understands.first))
        let unservedIDs = Set(unserved.map(\.userID))
        let known = profiles.filter { !$0.isFlexible && !unservedIDs.contains($0.userID) }

        if !served.isEmpty {
            let options = languages.filter { language in
                served.allSatisfy { $0.understands.contains(language) }
            }
            let listenerLists = served.map(\.understands)

            let best = options.min { lhs, rhs in
                let lhsCount = known.count(where: { $0.understands.contains(lhs) })
                let rhsCount = known.count(where: { $0.understands.contains(rhs) })
                if lhsCount != rhsCount {
                    return lhsCount > rhsCount
                }

                let order = preferenceOrder(lhs, rhs, lists: listenerLists)
                if order != .orderedSame {
                    return order == .orderedAscending
                }

                let lhsIsOriginal = lhs == original?.language
                let rhsIsOriginal = rhs == original?.language
                if lhsIsOriginal != rhsIsOriginal {
                    return lhsIsOriginal
                }

                return (languages.firstIndex(of: lhs) ?? 0) < (languages.firstIndex(of: rhs) ?? 0)
            }

            if let best, let track = track(in: best, audio: audio, original: original) {
                return AudioChoice(
                    index: track.index,
                    language: track.language,
                    reason: .listeners(served.map(\.name)),
                    unservedListeners: unservedNames,
                    unservedLanguages: unservedLanguages
                )
            }
        }

        // b. Original unless someone with known languages can't follow it.
        let objectors = known.filter { !$0.prefersOriginalAudio && !understands($0, original?.language) }

        if !objectors.isEmpty {
            let options = languages.filter { language in
                known.allSatisfy { $0.understands.contains(language) }
            }
            let knownLists = known.map(\.understands)

            let best = options.min { lhs, rhs in
                let order = preferenceOrder(lhs, rhs, lists: knownLists)
                if order != .orderedSame {
                    return order == .orderedAscending
                }
                return (languages.firstIndex(of: lhs) ?? 0) < (languages.firstIndex(of: rhs) ?? 0)
            }

            if let best, let track = track(in: best, audio: audio, original: original) {
                return AudioChoice(
                    index: track.index,
                    language: track.language,
                    reason: .everyoneUnderstands(best),
                    unservedListeners: unservedNames,
                    unservedLanguages: unservedLanguages
                )
            }
        }

        // c. The original track.
        return AudioChoice(
            index: original?.index,
            language: original?.language,
            reason: .original,
            unservedListeners: unservedNames,
            unservedLanguages: unservedLanguages
        )
    }

    /// The track to play for a language: the original track in its own language, else the best candidate.
    private static func track(
        in language: String,
        audio: [CouchStreamCandidate],
        original: CouchStreamCandidate?
    ) -> CouchStreamCandidate? {
        if let original, original.language == language {
            return original
        }

        return bestCandidate(audio.filter { $0.language == language })
    }
}

// MARK: - Subtitles

extension CouchLanguageRule {

    private struct SubtitleChoice {
        let index: Int
        let language: String?
        let reason: CouchLanguageDecision.SubtitleReason
    }

    private static func chooseSubtitles(
        profiles: [CouchLanguageProfile],
        subtitles: [CouchStreamCandidate],
        audioLanguage: String?
    ) -> SubtitleChoice {

        let needers = profiles.filter { profile in
            guard profile.readsSubtitles, profile.subtitleMode != .none else { return false }

            if profile.subtitleMode == .always {
                return true
            }

            return !profile.isFlexible && !understands(profile, audioLanguage)
        }

        // No needers: only forced subtitles for the audio language, as Jellyfin does.
        guard !needers.isEmpty else {
            let wantsForced = profiles.contains { $0.subtitleMode != .none }
            let forced = subtitles.filter { $0.isForced && ($0.language == nil || $0.language == audioLanguage) }

            if wantsForced, let track = bestCandidate(forced) {
                return SubtitleChoice(index: track.index, language: track.language, reason: .forcedOnly)
            }

            return SubtitleChoice(index: -1, language: nil, reason: .notNeeded)
        }

        let full = subtitles.filter { !$0.isForced && $0.language != nil }
        let languages = trackLanguages(full, original: nil)
        let neederNames = needers.map(\.name)
        // People without any known reading language accept any language.
        let readLists = needers.map(\.reads).filter { !$0.isEmpty }

        func reads(_ profile: CouchLanguageProfile, _ language: String) -> Bool {
            profile.reads.isEmpty || profile.reads.contains(language)
        }

        func ordered(_ lhs: String, _ rhs: String) -> Bool {
            let order = preferenceOrder(lhs, rhs, lists: readLists)
            if order != .orderedSame {
                return order == .orderedAscending
            }
            return (languages.firstIndex(of: lhs) ?? 0) < (languages.firstIndex(of: rhs) ?? 0)
        }

        let shared = languages.filter { language in
            needers.allSatisfy { reads($0, language) }
        }

        if let language = shared.min(by: ordered), let track = bestCandidate(full.filter { $0.language == language }) {
            let isAlwaysOnOnly = needers.allSatisfy { $0.subtitleMode == .always && understands($0, audioLanguage) }

            return SubtitleChoice(
                index: track.index,
                language: language,
                reason: isAlwaysOnOnly ? .alwaysOn(neederNames) : .neededBy(neederNames)
            )
        }

        // No language every needer reads: the one read by the most needers.
        let partial = languages
            .map { language in (language, needers.count(where: { reads($0, language) })) }
            .filter { $0.1 > 0 }
            .min { lhs, rhs in
                if lhs.1 != rhs.1 {
                    return lhs.1 > rhs.1
                }
                return ordered(lhs.0, rhs.0)
            }

        if let language = partial?.0, let track = bestCandidate(full.filter { $0.language == language }) {
            return SubtitleChoice(
                index: track.index,
                language: language,
                reason: .partial(missing: needers.filter { !reads($0, language) }.map(\.name))
            )
        }

        return SubtitleChoice(index: -1, language: nil, reason: .noSharedLanguage(neederNames))
    }
}

// MARK: - Helpers

extension CouchLanguageRule {

    /// Whether a person understands audio in a language. Unknown languages and flexible people always do.
    private static func understands(_ profile: CouchLanguageProfile, _ language: String?) -> Bool {
        guard let language else { return true }

        return profile.isFlexible || profile.understands.contains(language)
    }

    /// The preferred track among tracks in one language: plays without a transcode, then default, then lowest index.
    private static func bestCandidate(_ candidates: [CouchStreamCandidate]) -> CouchStreamCandidate? {
        candidates.min(by: isBetterCandidate)
    }

    private static func isBetterCandidate(_ lhs: CouchStreamCandidate, _ rhs: CouchStreamCandidate) -> Bool {
        if lhs.isPlayableWithoutTranscode != rhs.isPlayableWithoutTranscode {
            return lhs.isPlayableWithoutTranscode
        }
        if lhs.isDefault != rhs.isDefault {
            return lhs.isDefault
        }
        return lhs.index < rhs.index
    }

    /// The known languages of the tracks, ordered by their best track (the original first).
    private static func trackLanguages(_ candidates: [CouchStreamCandidate], original: CouchStreamCandidate?) -> [String] {
        let sorted = candidates.sorted { lhs, rhs in
            if let original, lhs.index == original.index || rhs.index == original.index {
                return lhs.index == original.index && rhs.index != original.index
            }
            return isBetterCandidate(lhs, rhs)
        }

        return CouchLanguageCode.unique(sorted.map(\.language))
    }

    /// Lowest summed rank first; on a tie, the first list (couch order) that ranks them differently.
    /// A language missing from a list ranks after every listed language.
    private static func preferenceOrder(_ lhs: String, _ rhs: String, lists: [[String]]) -> ComparisonResult {
        guard lhs != rhs else { return .orderedSame }

        func rank(_ language: String, in list: [String]) -> Int {
            list.firstIndex(of: language) ?? list.count + 100
        }

        let lhsSum = lists.reduce(0) { $0 + rank(lhs, in: $1) }
        let rhsSum = lists.reduce(0) { $0 + rank(rhs, in: $1) }

        if lhsSum != rhsSum {
            return lhsSum < rhsSum ? .orderedAscending : .orderedDescending
        }

        for list in lists {
            let lhsRank = rank(lhs, in: list)
            let rhsRank = rank(rhs, in: list)

            if lhsRank != rhsRank {
                return lhsRank < rhsRank ? .orderedAscending : .orderedDescending
            }
        }

        return .orderedSame
    }
}
