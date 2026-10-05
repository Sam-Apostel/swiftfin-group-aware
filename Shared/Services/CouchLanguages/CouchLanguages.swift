//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import FactoryKit
import Foundation
import JellyfinAPI

/// Glue between the couch language rule and playback.
///
/// The build hook in `MediaPlayerItem.build`, the item view label and the Playback menu all
/// call `decision(...)`, so they always agree on what will play.
@MainActor
enum CouchLanguages {

    /// The couch's audio and subtitle pick for a media source.
    ///
    /// Only the axes without an explicit index are decided. Reads cached profiles only (no network);
    /// starts a throttled background refresh of the profiles when they are older than 10 minutes.
    ///
    /// - Returns: `nil` when: no current session, the couch is solo, `Defaults[.Couch.autoLanguages]` is off,
    ///   the item is live TV, both indices are explicit, there is nothing to choose, or nobody on the couch
    ///   has any language set.
    ///   With a `nil` result playback behaves exactly as without couch languages.
    /// - Parameter deviceProfile: `nil` builds one from the playback defaults. Direct play and subtitle profiles
    ///   don't depend on the bitrate, so views get the same pick as `MediaPlayerItem.build`.
    static func decision(
        for mediaSource: MediaSourceInfo,
        item: BaseItemDto,
        audioStreamIndex: Int?,
        subtitleStreamIndex: Int?,
        deviceProfile: DeviceProfile? = nil
    ) -> CouchLanguageDecision? {

        guard let userSession = Container.shared.currentUserSession() else { return nil }

        let couch = userSession.couch

        guard couch.isGroup,
              Defaults[.Couch.autoLanguages],
              !item.isLiveStream,
              audioStreamIndex == nil || subtitleStreamIndex == nil
        else { return nil }

        let deviceProfile = deviceProfile ?? DeviceProfile.build(
            for: Defaults[.VideoPlayer.videoPlayerType],
            compatibilityMode: Defaults[.VideoPlayer.Playback.compatibilityMode]
        )

        let audio = audioCandidates(in: mediaSource, deviceProfile: deviceProfile)
        let subtitles = subtitleCandidates(in: mediaSource, deviceProfile: deviceProfile)

        let decidesAudio = audioStreamIndex == nil && audio.count > 1
        let decidesSubtitles = subtitleStreamIndex == nil && subtitles.isNotEmpty

        // Nothing to choose: leave everything to the server, as before.
        guard decidesAudio || decidesSubtitles else { return nil }

        let store = Container.shared.couchLanguageStore()
        store.refreshInBackgroundIfNeeded(couch: couch, in: userSession)

        let profiles = store.profiles(for: couch)

        // Nobody has languages set (the Jellyfin default): Couchfin has nothing to go on and
        // leaves the pick to the server, so a file's default subtitles still play as before.
        guard profiles.contains(where: { !$0.isFlexible || ($0.readsSubtitles && $0.subtitleMode == .always) }) else {
            return nil
        }

        return CouchLanguageRule.decide(
            profiles: profiles,
            audio: audio,
            subtitles: subtitles,
            fixedAudioIndex: audioStreamIndex,
            decideSubtitles: subtitleStreamIndex == nil
        )
    }

    /// The audio tracks the player offers, with the same filter as `MediaPlayerItem.init`.
    static func audioCandidates(
        in mediaSource: MediaSourceInfo,
        deviceProfile: DeviceProfile
    ) -> [CouchStreamCandidate] {
        (mediaSource.mediaStreams ?? [])
            .filter { $0.type == .audio && $0.isExternal != true }
            .compactMap { stream -> CouchStreamCandidate? in
                guard let index = stream.index else { return nil }

                let isPlayable = deviceProfile.canPlay(
                    type: .video,
                    audioCodec: stream.codec,
                    container: mediaSource.container
                )

                return CouchStreamCandidate(
                    index: index,
                    language: stream.language,
                    isDefault: stream.isDefault == true,
                    isForced: stream.isForced == true,
                    isPlayableWithoutTranscode: isPlayable
                )
            }
    }

    /// The subtitle tracks the player offers, with the same filter as `MediaPlayerItem.init`.
    static func subtitleCandidates(
        in mediaSource: MediaSourceInfo,
        deviceProfile: DeviceProfile
    ) -> [CouchStreamCandidate] {
        let compatibilityMode = Defaults[.VideoPlayer.Playback.compatibilityMode]

        return (mediaSource.mediaStreams ?? [])
            .filter { stream in
                stream.type == .subtitle
                    && stream.deliveryMethod != .drop
                    && !(compatibilityMode == .directPlay
                        && stream.isExternal == true
                        && stream.isTextSubtitleStream != true)
            }
            .compactMap { stream -> CouchStreamCandidate? in
                guard let index = stream.index else { return nil }

                let deliveryMethods: [SubtitleDeliveryMethod] = [.embed, .external, .hls]
                let isPlayable = stream.isTextSubtitleStream == true
                    || deliveryMethods.contains { deviceProfile.canPlay(subtitleFormat: stream.codec, method: $0) }

                return CouchStreamCandidate(
                    index: index,
                    language: stream.language,
                    isDefault: stream.isDefault == true,
                    isForced: stream.isForced == true,
                    isPlayableWithoutTranscode: isPlayable
                )
            }
    }

    /// The localized name of a language code, e.g. "Dutch" for `dut`, `nld` or `nl-BE`.
    ///
    /// `L10n.unknown` for `nil` and unknown markers like `und`.
    nonisolated static func displayName(forLanguage code: String?) -> String {
        guard let canonical = CouchLanguageCode.canonical(code) else { return L10n.unknown }

        let lookupCode = CouchLanguageCode.twoLetter(canonical) ?? canonical

        return Locale.current.localizedString(forLanguageCode: lookupCode) ?? canonical.uppercased()
    }
}

// MARK: - Summaries

extension CouchLanguageDecision {

    /// "Dutch audio", "Original audio (English)" or "Original audio".
    var audioSummary: String {
        let language = audioLanguage.map { CouchLanguages.displayName(forLanguage: $0) }

        switch audioReason {
        case .original:
            if let language {
                return L10n.CouchLanguages.originalAudioIn(language)
            }
            return L10n.CouchLanguages.originalAudio

        case .listeners, .everyoneUnderstands:
            if let language {
                return L10n.CouchLanguages.audio(language)
            }
            return L10n.CouchLanguages.originalAudio

        case .userChoice:
            if let language {
                return L10n.CouchLanguages.audio(language)
            }
            return L10n.CouchLanguages.chosenAudio
        }
    }

    /// "no subtitles", "Dutch subtitles" or "forced subtitles only".
    var subtitleSummary: String {
        switch subtitleReason {
        case .userChoice:
            return L10n.CouchLanguages.chosenSubtitles

        case .forcedOnly:
            return L10n.CouchLanguages.forcedSubtitlesOnly

        case .fileDefault:
            guard let subtitleStreamIndex, subtitleStreamIndex >= 0 else {
                return L10n.CouchLanguages.noSubtitles
            }
            guard let subtitleLanguage else {
                return L10n.CouchLanguages.genericSubtitles
            }

            return L10n.CouchLanguages.subtitles(CouchLanguages.displayName(forLanguage: subtitleLanguage))

        case .notNeeded, .neededBy, .alwaysOn, .partial, .noSharedLanguage:
            guard let subtitleStreamIndex, subtitleStreamIndex >= 0 else {
                return L10n.CouchLanguages.noSubtitles
            }

            return L10n.CouchLanguages.subtitles(CouchLanguages.displayName(forLanguage: subtitleLanguage))
        }
    }

    /// Why, in a few words. In order of priority: listeners ("Tuur is on the couch"), unserved listeners
    /// ("no Dutch audio for Tuur"), everyone understands ("everyone understands Dutch"), subtitles needed
    /// ("for Sam and Lisa"), always on ("Sam always wants subtitles"), partial or no shared language,
    /// the file's default subtitles.
    var reasonSummary: String? {
        if case let .listeners(names) = audioReason, names.isNotEmpty {
            let joinedNames = Self.joined(names)

            return names.count == 1
                ? L10n.CouchLanguages.isOnTheCouch(joinedNames)
                : L10n.CouchLanguages.areOnTheCouch(joinedNames)
        }

        if unservedListeners.isNotEmpty {
            let languages = unservedLanguages.isEmpty
                ? L10n.unknown
                : Self.joined(unservedLanguages.map { CouchLanguages.displayName(forLanguage: $0) })

            return L10n.CouchLanguages.noAudio(language: languages, names: Self.joined(unservedListeners))
        }

        if case let .everyoneUnderstands(language) = audioReason {
            return L10n.CouchLanguages.everyoneUnderstands(CouchLanguages.displayName(forLanguage: language))
        }

        switch subtitleReason {
        case let .neededBy(names) where names.isNotEmpty:
            return L10n.CouchLanguages.neededBy(Self.joined(names))

        case let .alwaysOn(names) where names.isNotEmpty:
            return names.count == 1
                ? L10n.CouchLanguages.alwaysWantsSubtitles(Self.joined(names))
                : L10n.CouchLanguages.alwaysWantSubtitles(Self.joined(names))

        case let .partial(missing: names) where names.isNotEmpty:
            let language = CouchLanguages.displayName(forLanguage: subtitleLanguage)

            return names.count == 1
                ? L10n.CouchLanguages.doesNotRead(Self.joined(names), language: language)
                : L10n.CouchLanguages.doNotRead(Self.joined(names), language: language)

        case let .noSharedLanguage(names) where names.isNotEmpty:
            return names.count == 1
                ? L10n.CouchLanguages.noSubtitlesReadableBy(Self.joined(names))
                : L10n.CouchLanguages.noSubtitlesReadableByAll(Self.joined(names))

        case .fileDefault:
            return L10n.CouchLanguages.fileDefaultSubtitles

        default:
            return nil
        }
    }

    /// "Dutch audio · no subtitles — Tuur is on the couch"
    var summary: String {
        if let reasonSummary {
            return L10n.CouchLanguages.summary(audio: audioSummary, subtitles: subtitleSummary, reason: reasonSummary)
        }

        return L10n.CouchLanguages.summary(audio: audioSummary, subtitles: subtitleSummary)
    }

    /// A localized list, like `CouchGroup.displayNames`.
    private static func joined(_ values: [String]) -> String {
        ListFormatter.localizedString(byJoining: values)
    }
}
