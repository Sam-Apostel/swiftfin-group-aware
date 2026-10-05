//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import FactoryKit
import JellyfinAPI
import SwiftUI

/// The Languages sections of `CouchSettingsView`: the auto-languages toggle and one row per stored user
/// on this server, with what Couchfin assumes about their languages. A row opens the person page.
struct CouchLanguagesSection: View {

    @Default(.Couch.autoLanguages)
    private var autoLanguages

    @InjectedObject(\.userSessionManager)
    private var userSessionManager: UserSessionManager

    @InjectedObject(\.couchLanguageStore)
    private var store: CouchLanguageStore

    @Router
    private var router

    /// Stored users on the current server, sorted by name (like the Kids list).
    @State
    private var users: [UserState] = []

    var body: some View {
        toggleSection

        peopleSection
            .onAppear {
                loadUsers()
            }
            .onChange(of: store.revision) {
                // A refresh may have renamed someone
                loadUsers()
            }
    }

    // MARK: - Toggle

    @ViewBuilder
    private var toggleSection: some View {
        Section {
            Toggle(L10n.CouchLanguageSettings.pickLanguagesForTheCouch, isOn: $autoLanguages)
        } header: {
            Text(L10n.CouchLanguageSettings.languages)
        } footer: {
            Text(L10n.CouchLanguageSettings.pickLanguagesFooter)
        }
    }

    // MARK: - People

    @ViewBuilder
    private var peopleSection: some View {
        Section {
            if users.isEmpty {
                Text(L10n.CouchSettings.noUsers)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(users, id: \.id) { user in
                    ChevronButton(
                        action: {
                            router.route(to: .couchLanguageProfile(userID: user.id))
                        },
                        label: {
                            rowLabel(user: user)
                        }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func rowLabel(user: UserState) -> some View {
        HStack(spacing: UIDevice.isTV ? 20 : 12) {
            if let server = userSessionManager.currentSession?.server {
                UserProfileImage(
                    userID: user.id,
                    source: user.profileImageSource(
                        client: server.client
                    ),
                    pipeline: .Swiftfin.local
                )
                .frame(width: UIDevice.isTV ? 60 : 36, height: UIDevice.isTV ? 60 : 36)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(user.username)
                    .lineLimit(1)

                Text(summary(for: user))
                    .font(UIDevice.isTV ? .caption : .footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    // MARK: - Helpers

    private func summary(for user: UserState) -> String {
        // Read `revision` so edits on the person page update the row.
        _ = store.revision

        let profile = store.profile(for: user)

        return profile.settingsSummary ?? L10n.CouchLanguageSettings.noLanguagesSet(profile.name)
    }

    private func loadUsers() {
        guard let serverID = userSessionManager.currentSession?.server.id else {
            users = []
            return
        }

        users = StoredValues[.User.users]
            .filter { $0.serverID == serverID }
            .sorted { $0.username.localizedStandardCompare($1.username) == .orderedAscending }
    }
}

// MARK: - Display helpers

extension CouchLanguageProfile {

    /// Localized names of canonical codes, e.g. "English, French". `nil` when empty.
    static func languageNames(_ codes: [String]) -> String? {
        guard codes.isNotEmpty else { return nil }

        return codes
            .map { CouchLanguages.displayName(forLanguage: $0) }
            .joined(separator: ", ")
    }

    /// The localized title of a subtitle mode, e.g. "Smart".
    static func displayTitle(of mode: CouchSubtitleMode) -> String {
        SubtitlePlaybackMode(rawValue: mode.rawValue)?.displayTitle ?? mode.rawValue
    }

    /// One line for the Couch settings row, e.g. "Dutch audio · doesn't read subtitles" or
    /// "Original audio · Dutch subtitles (Smart) · also understands English, French".
    ///
    /// `nil` when nothing is known about this person, so Couchfin won't adjust for them.
    var settingsSummary: String? {
        guard understands.isNotEmpty || reads.isNotEmpty else { return nil }

        var parts: [String] = [audioSummaryPart]

        if let subtitlePart = subtitleSummaryPart {
            parts.append(subtitlePart)
        }

        let alsoUnderstood = understands.filter { language in
            language != audioLanguage && !(subtitleMode == .smart && language == subtitleLanguage)
        }

        if let names = Self.languageNames(alsoUnderstood) {
            parts.append(L10n.CouchLanguageSettings.alsoUnderstandsSummary(names))
        }

        return parts.joined(separator: " · ")
    }

    private var audioSummaryPart: String {
        guard let audioLanguage else { return L10n.CouchLanguages.originalAudio }

        return L10n.CouchLanguages.audio(CouchLanguages.displayName(forLanguage: audioLanguage))
    }

    private var subtitleSummaryPart: String? {
        guard readsSubtitles else { return L10n.CouchLanguageSettings.doesNotReadSubtitlesShort }

        if subtitleMode == .none {
            return L10n.CouchLanguages.noSubtitles
        }

        let modeTitle = Self.displayTitle(of: subtitleMode)

        guard let subtitleLanguage else {
            return subtitleMode == .always
                ? L10n.CouchLanguageSettings.subtitlesWithoutLanguage(mode: modeTitle)
                : nil
        }

        let language = CouchLanguages.displayName(forLanguage: subtitleLanguage)

        if subtitleMode == .default {
            return L10n.CouchLanguages.subtitles(language)
        }

        return L10n.CouchLanguageSettings.subtitles(language, mode: modeTitle)
    }
}
