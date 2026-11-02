//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Foundation
import JellyfinAPI
import Logging

/// Remembers the subtitle choice each user makes in the player and applies it to whatever plays next.
///
/// The choice is kept on the device (per user) and written to the user's server configuration,
/// so other devices and the server's own default track follow it too.
enum SubtitlePreferenceStore {

    private static let logger = Logger.swiftfin()

    // MARK: - Read

    /// The choice remembered on this device, if any.
    static func localPreference(for userID: String) -> SubtitlePreference? {
        Defaults[.subtitlePreferences][userID]
    }

    /// The remembered choice, falling back to the server configuration loaded when the session started.
    static func preference(for userSession: UserSession) -> SubtitlePreference? {
        if let local = localPreference(for: userSession.user.id) {
            return local
        }

        guard let configuration = userSession.user.data.configuration else { return nil }

        let language = SubtitlePreference.normalizedLanguage(configuration.subtitleLanguagePreference)

        switch configuration.subtitleMode ?? .default {
        case SubtitlePlaybackMode.none:
            return .off
        case .always where language != nil:
            return SubtitlePreference(isEnabled: true, language: language, flavour: .regular)
        case .onlyForced where language != nil:
            return SubtitlePreference(isEnabled: true, language: language, flavour: .forced)
        default:
            return nil
        }
    }

    /// The subtitle index to play from `mediaStreams`, or `nil` to keep the default behaviour.
    static func preferredSubtitleIndex(
        in mediaStreams: [MediaStream]?,
        userSession: UserSession?
    ) -> Int? {
        guard let userSession,
              let rememberedPreference = preference(for: userSession)
        else { return nil }

        let subtitleStreams = MediaPlayerItem.playableSubtitleStreams(in: mediaStreams)

        return rememberedPreference.preferredIndex(in: subtitleStreams)
    }

    // MARK: - Write

    /// Records a subtitle track the user picked in the player. `-1` or `nil` means off.
    @MainActor
    static func recordUserSelection(
        index: Int?,
        in subtitleStreams: [MediaStream],
        userSession: UserSession?
    ) {
        guard let userSession else { return }

        let preference: SubtitlePreference

        if let index, index != -1 {
            guard let stream = subtitleStreams.first(where: { $0.index == index }) else { return }

            preference = SubtitlePreference(stream: stream)
        } else {
            preference = .off
        }

        Defaults[.subtitlePreferences][userSession.user.id] = preference

        updateServerConfiguration(userSession: userSession, preference: preference)
    }

    /// Drops the choice remembered on this device, so the server configuration applies again.
    ///
    /// Used when the choice is forgotten or subtitle settings are changed by hand.
    static func clearLocalPreference(for userID: String?) {
        guard let userID else { return }

        Defaults[.subtitlePreferences][userID] = nil
    }

    /// Fire-and-forget: reads the latest configuration, applies the preference and writes it back.
    @MainActor
    private static func updateServerConfiguration(userSession: UserSession, preference: SubtitlePreference) {
        Task { @MainActor in
            do {
                let user = try await userSession.client.send(Paths.getCurrentUser).value

                var configuration = user.configuration ?? UserConfiguration()
                configuration.isRememberSubtitleSelections = true

                if preference.isEnabled {
                    configuration.subtitleMode = preference.flavour == .forced
                        ? SubtitlePlaybackMode.onlyForced
                        : SubtitlePlaybackMode.always

                    if let language = preference.language {
                        configuration.subtitleLanguagePreference = language
                    }
                } else {
                    configuration.subtitleMode = SubtitlePlaybackMode.none
                }

                let request = Paths.updateUserConfiguration(userID: userSession.user.id, configuration)
                try await userSession.client.send(request)

                userSession.user.data.configuration = configuration
            } catch {
                logger.warning("Unable to save subtitle preference to the server: \(error.localizedDescription)")
            }
        }
    }
}
