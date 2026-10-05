//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Defaults
import FactoryKit
import Foundation
import Get
import JellyfinAPI
import Logging

extension Container {

    var couchLanguageStore: Factory<CouchLanguageStore> {
        self { @MainActor in CouchLanguageStore() }
            .singleton
    }
}

extension CouchLanguageExtras: Storable {}

enum CouchLanguageSaveResult: Equatable {
    /// Written to the person's Jellyfin configuration: also used when they watch alone, in every Jellyfin app.
    case savedToJellyfin
    /// The Jellyfin configuration can't be written from here: kept as a couch-only override.
    case savedForCouchOnly
    /// Nothing changed.
    case failed(String)
}

/// Everyone's language profile: their Jellyfin preferences (`UserState.data.configuration`)
/// plus the couch-only extras.
///
/// Reading is synchronous and offline: profiles come from the local cache, so pressing Play makes no network call.
/// Writing is local first, then best-effort to the server; nothing here throws to the UI.
///
/// The extras are cached per user in `StoredValues` and synced through that person's **own** DisplayPreferences row
/// `swiftfin-couch-languages` (client `swiftfin-couch`), written with their own member session.
/// Every user may write their own display preferences, and the row follows them to every device with their token.
/// The newest `updatedAt` wins.
@MainActor
final class CouchLanguageStore: ObservableObject {

    /// Bumped on every cache change. Views observe it to re-read profiles.
    @Published
    private(set) var revision: Int = 0

    /// How long a couch's profiles stay fresh before `refreshIfNeeded` refreshes them again.
    static let refreshInterval: TimeInterval = 10 * 60

    /// Profiles are memoised until the revision changes, and at most this long, so preferences
    /// refreshed elsewhere (e.g. at couch sign-in) are picked up.
    private static let profileMemoLifetime: TimeInterval = 30

    private struct MemoizedProfile {
        let profile: CouchLanguageProfile
        let date: Date
    }

    private struct PreferenceWriteAttempt {
        let client: JellyfinClient
        let request: Request<UserDto>
    }

    private var profileMemo: [String: MemoizedProfile] = [:]
    private var lastRefreshByCouchID: [String: Date] = [:]
    private var syncChain: Task<Void, Never>?

    private let logger = Logger.swiftfin()

    init() {}

    // MARK: - Reading

    /// The cached couch-only extras of a user.
    func extras(for userID: String) -> CouchLanguageExtras {
        StoredValues[Self.extrasKey(userID: userID)]
    }

    /// A user's language profile: their cached Jellyfin configuration plus their extras.
    func profile(for user: UserState) -> CouchLanguageProfile {
        if let memo = profileMemo[user.id], Date.now.timeIntervalSince(memo.date) < Self.profileMemoLifetime {
            return memo.profile
        }

        let profile = makeProfile(for: user)
        profileMemo[user.id] = MemoizedProfile(profile: profile, date: .now)
        return profile
    }

    /// Profiles of everyone on the couch, in couch order (primary first).
    func profiles(for couch: CouchGroup) -> [CouchLanguageProfile] {
        couch.members.map { profile(for: $0) }
    }

    /// Whether `saveJellyfinPreferences` can write this user's Jellyfin configuration:
    /// with their own session (when their policy allows it) or as an administrator.
    func canEditJellyfinPreferences(for user: UserState, in session: UserSession) -> Bool {
        if session.user.data.policy?.isAdministrator == true {
            return true
        }

        guard memberSession(for: user, in: session) != nil else { return false }

        let policy = user.data.policy
        return policy?.isAdministrator == true || policy?.enableUserPreferenceAccess != false
    }

    // MARK: - Refreshing

    /// Refreshes the users' Jellyfin preferences and syncs their extras. Never throws: failing users are skipped.
    func refresh(users: [UserState], in session: UserSession) async {
        for user in users where user.serverID == session.server.id {
            await refreshUserData(user, in: session)

            await enqueueSync { [weak self] in
                await self?.syncExtras(for: user, in: session)
            }
        }

        bumpRevision()
    }

    /// Refreshes a group couch at most every 10 minutes. Does nothing for a solo couch.
    func refreshIfNeeded(couch: CouchGroup, in session: UserSession) async {
        guard beginRefreshIfNeeded(couch: couch) else { return }

        await refresh(users: couch.members, in: session)
    }

    /// Fire-and-forget `refreshIfNeeded`, safe to call often (e.g. from the playback build or a view).
    func refreshInBackgroundIfNeeded(couch: CouchGroup, in session: UserSession) {
        guard beginRefreshIfNeeded(couch: couch) else { return }

        Task { [weak self] in
            await self?.refresh(users: couch.members, in: session)
        }
    }

    // MARK: - Saving

    /// Saves the extras locally right away (`updatedAt = .now`), then writes them to the person's
    /// DisplayPreferences row. Never throws; a failed write is retried by the next refresh.
    func saveExtras(_ extras: CouchLanguageExtras, for user: UserState, in session: UserSession) async {
        var stamped = extras.normalized()
        stamped.updatedAt = CouchLanguageExtras.saveDate()

        StoredValues[Self.extrasKey(userID: user.id)] = stamped
        bumpRevision()

        await enqueueSync { [weak self] in
            await self?.syncExtras(for: user, in: session)
        }
    }

    /// Writes the person's Jellyfin audio and subtitle preferences.
    ///
    /// Uses the person's own session, else the primary user when they are an administrator. When the server
    /// refuses (401/403) or there is no usable session, the values are kept as a couch-only override.
    /// The whole configuration is fetched fresh first, because the server replaces it entirely.
    func saveJellyfinPreferences(
        audioLanguage: String?,
        subtitleLanguage: String?,
        subtitleMode: SubtitlePlaybackMode,
        for user: UserState,
        in session: UserSession
    ) async -> CouchLanguageSaveResult {

        for attempt in preferenceWriteAttempts(for: user, in: session) {
            do {
                let fresh = try await attempt.client.send(attempt.request).value

                // Never post a blank configuration: the server would reset every other setting.
                guard var configuration = fresh.configuration else {
                    logger.error("Couch languages: no configuration for user \(user.id), not saving")
                    return .failed(L10n.unknownError)
                }

                configuration.audioLanguagePreference = audioLanguage
                configuration.subtitleLanguagePreference = subtitleLanguage
                configuration.subtitleMode = subtitleMode

                try await attempt.client.send(Paths.updateUserConfiguration(userID: user.id, configuration))

                var data = fresh
                data.configuration = configuration
                user.data = data

                var current = self.extras(for: user.id)

                if current.overridesJellyfin {
                    current.overridesJellyfin = false
                    current.audioLanguage = nil
                    current.subtitleLanguage = nil
                    current.subtitleMode = nil

                    await saveExtras(current, for: user, in: session)
                }

                bumpRevision()
                return .savedToJellyfin
            } catch {
                if Self.isAccessDenied(error) {
                    logger.info("Couch languages: the server refused the preferences of user \(user.id), trying the next way")
                    continue
                }

                logger.error("Couch languages: saving the preferences of user \(user.id) failed: \(error.localizedDescription)")
                return .failed(error.localizedDescription)
            }
        }

        var current = self.extras(for: user.id)
        current.overridesJellyfin = true
        current.audioLanguage = audioLanguage
        current.subtitleLanguage = subtitleLanguage
        current.subtitleMode = CouchSubtitleMode(rawValue: subtitleMode.rawValue)

        await saveExtras(current, for: user, in: session)

        return .savedForCouchOnly
    }
}

// MARK: - Profiles

extension CouchLanguageStore {

    private static func extrasKey(userID: String) -> StoredValues.Key<CouchLanguageExtras> {
        StoredValues.Keys.UserKey(
            ownerID: userID,
            field: "couchLanguageExtras",
            default: CouchLanguageExtras()
        )
    }

    private func makeProfile(for user: UserState) -> CouchLanguageProfile {
        let configuration = user.data.configuration
        let extras = self.extras(for: user.id)

        let audioLanguage: String?
        let subtitleLanguage: String?
        let subtitleMode: CouchSubtitleMode

        if extras.overridesJellyfin {
            audioLanguage = extras.audioLanguage
            subtitleLanguage = extras.subtitleLanguage
            subtitleMode = extras.subtitleMode ?? .default
        } else {
            audioLanguage = configuration?.audioLanguagePreference
            subtitleLanguage = configuration?.subtitleLanguagePreference
            subtitleMode = (configuration?.subtitleMode)
                .flatMap { CouchSubtitleMode(rawValue: $0.rawValue) } ?? .default
        }

        return CouchLanguageProfile(
            userID: user.id,
            name: user.username,
            isKid: user.isKid,
            restrictionScore: user.restrictionScore,
            audioLanguagePreference: audioLanguage,
            subtitleLanguagePreference: subtitleLanguage,
            subtitleMode: subtitleMode,
            alsoUnderstands: extras.alsoUnderstands,
            alsoReads: extras.alsoReads,
            readsSubtitles: extras.readsSubtitles
        )
    }

    private func bumpRevision() {
        profileMemo.removeAll()
        revision &+= 1
    }
}

// MARK: - Sync

extension CouchLanguageStore {

    /// The person's own session: theirs on the couch, or an inert household session.
    private func memberSession(for user: UserState, in session: UserSession) -> UserSession? {
        session.session(forMemberID: user.id)
            ?? session.householdSessions().first { $0.user.id == user.id }
    }

    /// The client that may read and write the person's DisplayPreferences row.
    private func syncClient(for user: UserState, in session: UserSession) -> JellyfinClient? {
        if let memberSession = memberSession(for: user, in: session) {
            return memberSession.client
        }

        if session.user.data.policy?.isAdministrator == true {
            return session.client
        }

        return nil
    }

    private func preferenceWriteAttempts(for user: UserState, in session: UserSession) -> [PreferenceWriteAttempt] {
        var attempts: [PreferenceWriteAttempt] = []

        if let memberSession = memberSession(for: user, in: session) {
            attempts.append(PreferenceWriteAttempt(client: memberSession.client, request: Paths.getCurrentUser))
        }

        if session.user.id != user.id, session.user.data.policy?.isAdministrator == true {
            attempts.append(PreferenceWriteAttempt(client: session.client, request: Paths.getUserByID(userID: user.id)))
        }

        return attempts
    }

    private static func isAccessDenied(_ error: Error) -> Bool {
        guard case let .unacceptableStatusCode(statusCode)? = error as? Get.APIError else { return false }

        return statusCode == 401 || statusCode == 403
    }

    private func beginRefreshIfNeeded(couch: CouchGroup) -> Bool {
        guard couch.isGroup else { return false }

        if let lastRefresh = lastRefreshByCouchID[couch.id],
           Date.now.timeIntervalSince(lastRefresh) < Self.refreshInterval
        {
            return false
        }

        lastRefreshByCouchID[couch.id] = .now
        return true
    }

    /// Refreshes the cached Jellyfin user data (configuration and policy) of a user.
    private func refreshUserData(_ user: UserState, in session: UserSession) async {
        do {
            if user.storedAccessToken != nil {
                try await user.updateUserData(server: session.server)
            } else if session.user.data.policy?.isAdministrator == true {
                let response = try await session.client.send(Paths.getUserByID(userID: user.id))
                user.data = response.value
            }
        } catch {
            logger.error("Couch languages: refreshing the preferences of user \(user.id) failed: \(error.localizedDescription)")
        }
    }

    /// Runs syncs one at a time, so two read-modify-writes of a row never interleave.
    private func enqueueSync(_ operation: @escaping @MainActor () async -> Void) async {
        let previous = syncChain

        let task = Task { @MainActor in
            await previous?.value
            await operation()
        }

        syncChain = task
        await task.value
    }

    /// Makes the local cache and the person's DisplayPreferences row agree: the newest `updatedAt` wins.
    private func syncExtras(for user: UserState, in session: UserSession) async {
        guard let client = syncClient(for: user, in: session) else {
            logger.warning("Couch languages: no access token for user \(user.id), extras kept on this device only")
            return
        }

        do {
            let customPrefs = try await CouchDisplayPreferences.fetchCustomPrefs(
                displayPreferencesID: CouchLanguageExtras.displayPreferencesID,
                userID: user.id,
                client: client
            )

            let remote = CouchLanguageExtras.decode(
                customPrefsValue: customPrefs[CouchLanguageExtras.customPrefsKey] ?? nil
            )
            let local = extras(for: user.id)

            switch CouchLanguageExtras.syncWinner(local: local, remote: remote) {
            case .same:
                return

            case .remote:
                guard let remote else { return }

                StoredValues[Self.extrasKey(userID: user.id)] = remote
                bumpRevision()

            case .local:
                guard let encoded = local.encodedForCustomPrefs() else { return }

                // POST replaces the whole map: keep any other key of the row
                var updatedPrefs = customPrefs.compactMapValues { $0 }
                updatedPrefs[CouchLanguageExtras.customPrefsKey] = encoded

                try await CouchDisplayPreferences.postCustomPrefs(
                    updatedPrefs,
                    displayPreferencesID: CouchLanguageExtras.displayPreferencesID,
                    userID: user.id,
                    client: client
                )
            }
        } catch {
            logger.error("Couch languages: syncing the extras of user \(user.id) failed: \(error.localizedDescription)")
        }
    }
}
