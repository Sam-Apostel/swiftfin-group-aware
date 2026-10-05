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

/// One person's languages: their Jellyfin audio and subtitle preferences, the couch-only extras,
/// and what Couchfin derives from both.
///
/// All I/O goes through `CouchLanguageStore`, which never throws. The Jellyfin fields read from the store,
/// so a failed save reverts them by itself.
struct CouchLanguageProfileView: View {

    /// The three Jellyfin fields, saved together.
    private struct JellyfinFields: Equatable {
        var audioLanguage: String?
        var subtitleLanguage: String?
        var subtitleMode: SubtitlePlaybackMode
    }

    #if os(tvOS)
    typealias PlatformPicker = ListRowMenu
    #else
    typealias PlatformPicker = Picker
    #endif

    @InjectedObject(\.couchLanguageStore)
    private var store: CouchLanguageStore

    @InjectedObject(\.userSessionManager)
    private var userSessionManager: UserSessionManager

    @Router
    private var router

    @State
    private var user: UserState?
    /// The couch-only extras being edited; saved on change.
    @State
    private var extras = CouchLanguageExtras()
    @State
    private var canEditJellyfinPreferences = true
    @State
    private var lastSaveWasCouchOnly = false
    /// The fields being saved, shown until the save finishes.
    @State
    private var pendingFields: JellyfinFields?
    @State
    private var saveTask: Task<Void, Never>?
    @State
    private var error: Error?

    private let userID: String

    init(userID: String) {
        self.userID = userID
        self._user = State(initialValue: StoredValues[.User.users].first { $0.id == userID })
    }

    // MARK: - Body

    var body: some View {
        Group {
            if let user, let session = userSessionManager.currentSession {
                form(user: user, session: session)
            } else {
                ContentUnavailableView(
                    L10n.CouchLanguageSettings.personNotFound,
                    systemImage: "person.crop.circle.badge.questionmark"
                )
            }
        }
        .navigationTitle(user?.username ?? L10n.CouchLanguageSettings.languages)
        .errorMessage($error)
    }

    @ViewBuilder
    private func form(user: UserState, session: UserSession) -> some View {
        Form(systemImage: "character.bubble") {
            jellyfinSection(user: user)

            couchSection(user: user)

            assumptionsSection(user: user)
        }
        .onAppear {
            reload(in: session)
        }
        .onFirstAppear {
            // Not tied to the view's lifetime, so opening the language list doesn't cancel it
            Task {
                await store.refresh(users: [user], in: session)
                reload(in: session)
            }
        }
        .onChange(of: store.revision) {
            reload(in: session)
        }
        .onChange(of: extras) { _, newValue in
            saveExtrasIfChanged(newValue, for: user, in: session)
        }
    }

    // MARK: - Jellyfin settings

    @ViewBuilder
    private func jellyfinSection(user: UserState) -> some View {
        Section {
            CulturePicker(
                L10n.CouchLanguageSettings.audioLanguage,
                threeLetterISOLanguageName: fieldBinding(\JellyfinFields.audioLanguage, user: user)
            )

            CulturePicker(
                L10n.CouchLanguageSettings.subtitleLanguage,
                threeLetterISOLanguageName: fieldBinding(\JellyfinFields.subtitleLanguage, user: user)
            )

            PlatformPicker(
                L10n.subtitleMode,
                selection: fieldBinding(\JellyfinFields.subtitleMode, user: user)
            )
        } header: {
            HStack(spacing: 8) {
                Text(L10n.CouchLanguageSettings.jellyfinSettings)

                if pendingFields != nil {
                    ProgressView()
                }
            }
        } footer: {
            jellyfinFooter(user: user)
        }
    }

    @ViewBuilder
    private func jellyfinFooter(user: UserState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.CouchLanguageSettings.noneMeansOriginalAudio)

            Text(displayedFields(user: user).subtitleMode.description)

            if isCouchOnly {
                Text(L10n.CouchLanguageSettings.savedForCouchOnly(user.username))
            } else {
                Text(L10n.CouchLanguageSettings.alsoUsedWhenWatchingAlone(user.username))
            }
        }
    }

    // MARK: - On the couch

    @ViewBuilder
    private func couchSection(user: UserState) -> some View {
        Section {
            ChevronButton(
                L10n.CouchLanguageSettings.alsoUnderstands,
                content: languageNames(extras.alsoUnderstands)
            ) {
                router.route(to: .couchLanguageList(
                    title: L10n.CouchLanguageSettings.alsoUnderstands,
                    selection: $extras.alsoUnderstands
                ))
            }

            Toggle(
                L10n.CouchLanguageSettings.readsSubtitles,
                isOn: readsSubtitlesBinding(user: user)
            )

            ChevronButton(
                L10n.CouchLanguageSettings.alsoReads,
                content: languageNames(extras.alsoReads)
            ) {
                router.route(to: .couchLanguageList(
                    title: L10n.CouchLanguageSettings.alsoReads,
                    selection: $extras.alsoReads
                ))
            }
            .disabled(!readsSubtitles(user: user))
        } header: {
            Text(L10n.CouchLanguageSettings.onTheCouch)
        } footer: {
            Text(L10n.CouchLanguageSettings.onTheCouchFooter(user.username))
        }
    }

    // MARK: - What Couchfin assumes

    @ViewBuilder
    private func assumptionsSection(user: UserState) -> some View {
        let profile = currentProfile(user: user)

        Section {
            LabeledContent(
                L10n.CouchLanguageSettings.understands,
                value: CouchLanguageProfile.languageNames(profile.understands) ?? L10n.CouchLanguageSettings.notSet
            )

            if profile.readsSubtitles {
                LabeledContent(
                    L10n.CouchLanguageSettings.reads,
                    value: CouchLanguageProfile.languageNames(profile.reads) ?? L10n.CouchLanguageSettings.notSet
                )
            } else {
                LabeledContent(
                    L10n.CouchLanguageSettings.reads,
                    value: L10n.CouchLanguageSettings.doesNotReadSubtitles
                )
            }
        } header: {
            Text(L10n.CouchLanguageSettings.whatCouchfinAssumes)
        } footer: {
            if profile.isKid, profile.audioLanguage == nil {
                Text(L10n.CouchLanguageSettings.setAudioLanguageHint(user.username))
            }
        }
        .labeledContentStyle(.focusable)
    }

    // MARK: - Reading

    private var isCouchOnly: Bool {
        !canEditJellyfinPreferences || lastSaveWasCouchOnly || extras.overridesJellyfin
    }

    private func currentProfile(user: UserState) -> CouchLanguageProfile {
        // Read `revision` so saves and refreshes re-render.
        _ = store.revision

        return store.profile(for: user)
    }

    /// The saved Jellyfin fields: the couch-only override when there is one, else the cached Jellyfin configuration.
    private func storedFields(user: UserState) -> JellyfinFields {
        _ = store.revision

        let storedExtras = store.extras(for: user.id)

        if storedExtras.overridesJellyfin {
            return JellyfinFields(
                audioLanguage: storedExtras.audioLanguage,
                subtitleLanguage: storedExtras.subtitleLanguage,
                subtitleMode: storedExtras.subtitleMode.flatMap { SubtitlePlaybackMode(rawValue: $0.rawValue) } ?? .default
            )
        }

        let configuration = user.data.configuration

        return JellyfinFields(
            audioLanguage: configuration?.audioLanguagePreference,
            subtitleLanguage: configuration?.subtitleLanguagePreference,
            subtitleMode: configuration?.subtitleMode ?? .default
        )
    }

    /// The fields being saved, else the saved ones.
    private func displayedFields(user: UserState) -> JellyfinFields {
        pendingFields ?? storedFields(user: user)
    }

    private func fieldBinding<Value>(_ keyPath: WritableKeyPath<JellyfinFields, Value>, user: UserState) -> Binding<Value> {
        Binding(
            get: {
                displayedFields(user: user)[keyPath: keyPath]
            },
            set: { newValue in
                var fields = displayedFields(user: user)
                fields[keyPath: keyPath] = newValue
                saveJellyfinFields(fields, for: user)
            }
        )
    }

    private func readsSubtitles(user: UserState) -> Bool {
        extras.readsSubtitles ?? !user.isKid
    }

    private func readsSubtitlesBinding(user: UserState) -> Binding<Bool> {
        Binding(
            get: {
                readsSubtitles(user: user)
            },
            set: { newValue in
                extras.readsSubtitles = newValue
            }
        )
    }

    private func languageNames(_ codes: [String]) -> String {
        CouchLanguageProfile.languageNames(codes) ?? L10n.none
    }

    // MARK: - Loading

    private func reload(in session: UserSession) {
        guard let storedUser = StoredValues[.User.users].first(where: { $0.id == userID }) else {
            user = nil
            return
        }

        user = storedUser
        extras = store.extras(for: userID)
        canEditJellyfinPreferences = store.canEditJellyfinPreferences(for: storedUser, in: session)
    }

    // MARK: - Saving

    /// Saves only the couch-only fields of `newValue` on top of the stored extras, so the Jellyfin
    /// override written by `saveJellyfinPreferences` is never replaced by a stale copy.
    private func saveExtrasIfChanged(_ newValue: CouchLanguageExtras, for user: UserState, in session: UserSession) {
        var merged = store.extras(for: user.id)

        guard merged.alsoUnderstands != newValue.alsoUnderstands
            || merged.alsoReads != newValue.alsoReads
            || merged.readsSubtitles != newValue.readsSubtitles
        else { return }

        merged.alsoUnderstands = newValue.alsoUnderstands
        merged.alsoReads = newValue.alsoReads
        merged.readsSubtitles = newValue.readsSubtitles

        Task {
            await store.saveExtras(merged, for: user, in: session)
        }
    }

    /// Saves the three Jellyfin fields. Saves run one after another, so the last change wins.
    private func saveJellyfinFields(_ fields: JellyfinFields, for user: UserState) {
        guard let session = userSessionManager.currentSession else { return }

        pendingFields = fields

        let previousTask = saveTask

        saveTask = Task {
            await previousTask?.value

            let result = await store.saveJellyfinPreferences(
                audioLanguage: fields.audioLanguage,
                subtitleLanguage: fields.subtitleLanguage,
                subtitleMode: fields.subtitleMode,
                for: user,
                in: session
            )

            didSave(fields, result: result)
        }
    }

    private func didSave(_ fields: JellyfinFields, result: CouchLanguageSaveResult) {
        switch result {
        case .savedToJellyfin:
            lastSaveWasCouchOnly = false
        case .savedForCouchOnly:
            lastSaveWasCouchOnly = true
        case let .failed(message):
            error = ErrorMessage(message)
        }

        // A newer change may be waiting: keep showing it
        if pendingFields == fields {
            pendingFields = nil
        }
    }
}
