//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import Foundation
import JellyfinAPI
import Logging

extension Container {

    var serverPlaybackFactsStore: Factory<ServerPlaybackFactsStore> {
        self { @MainActor in ServerPlaybackFactsStore() }
            .singleton
    }
}

/// What Couchfin knows about each server's ability to convert video: its encoding setup (read by an administrator)
/// and the conversion speeds measured while playing. See `ServerPlaybackFactsSync` for where it's stored.
///
/// Cached on this device, read from the server once per launch.
@MainActor
final class ServerPlaybackFactsStore {

    /// An administrator re-reads the encoding setup when it's older than this.
    static let encodingRefreshInterval: TimeInterval = 24 * 60 * 60

    private static let cacheKey = "couchfin.serverPlaybackFacts.cache"

    private var factsByServerID: [String: ServerPlaybackFacts] = [:]
    private var refreshTasks: [String: Task<ServerPlaybackFacts, Never>] = [:]

    private let logger = Logger.swiftfin()

    init() {
        loadCache()
    }

    // MARK: - Queries

    /// What's known right now, without waiting for the server.
    func cachedFacts(for userSession: UserSession) -> ServerPlaybackFacts? {
        factsByServerID[userSession.server.id]
    }

    /// What's known about the server of `userSession`, read from the server the first time per launch.
    func facts(for userSession: UserSession) async -> ServerPlaybackFacts {
        let serverID = userSession.server.id

        if let task = refreshTasks[serverID] {
            _ = await task.value
            return factsByServerID[serverID] ?? .empty
        }

        let task = Task { @MainActor in
            await self.refresh(userSession: userSession)
        }

        refreshTasks[serverID] = task
        _ = await task.value

        return factsByServerID[serverID] ?? .empty
    }

    // MARK: - Recording

    /// Records how fast the server converted a class of video in one playback session, and saves it to the server.
    func record(fps: Double, samples: Int, streamClass: TranscodeStreamClass, userSession: UserSession) {
        let serverID = userSession.server.id
        let userID = userSession.user.id
        let client = userSession.client

        Task { @MainActor in
            _ = await self.facts(for: userSession)

            let current = self.factsByServerID[serverID] ?? .empty
            let updated = current.recording(fps: fps, samples: samples, streamClass: streamClass, at: .now)
            self.set(updated, serverID: serverID)

            self.logger.info(
                "Server conversion speed",
                metadata: [
                    "class": .string(streamClass.key),
                    "fps": .stringConvertible(Int(fps.rounded())),
                ]
            )

            do {
                try await LighterCopyStore.postCustomPrefs(
                    ServerPlaybackFactsSync.customPrefs(for: updated),
                    userID: userID,
                    client: client,
                    preferencesID: ServerPlaybackFactsSync.displayPreferencesID
                )
            } catch {
                self.logger.warning("Unable to save the server facts: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Refresh

    /// Reads the stored copies (everyone's for an administrator), merges them, re-reads the encoding setup
    /// when an administrator can and it's stale, and writes the result back to every copy that differs.
    private func refresh(userSession: UserSession) async -> ServerPlaybackFacts {
        let serverID = userSession.server.id
        let userID = userSession.user.id
        let client = userSession.client
        let isAdministrator = userSession.user.data.policy?.isAdministrator == true
        let preferencesID = ServerPlaybackFactsSync.displayPreferencesID

        var userIDs = [userID]

        if isAdministrator, let users = try? await client.send(Paths.getUsers()).value {
            userIDs = users.compactMap(\.id)
        }

        var stored: [String: [String: String?]] = [:]

        for id in userIDs {
            if let customPrefs = try? await LighterCopyStore.fetchCustomPrefs(userID: id, client: client, preferencesID: preferencesID) {
                stored[id] = customPrefs
            }
        }

        var merged = ServerPlaybackFactsSync.merge(
            [factsByServerID[serverID] ?? .empty] + stored.values.map(ServerPlaybackFactsSync.facts(in:))
        )

        let encodingAge = merged.encoding.map { Date.now.timeIntervalSince($0.updatedAt) } ?? .infinity

        if isAdministrator, encodingAge > Self.encodingRefreshInterval, let encoding = await Self.fetchEncodingFacts(client: client) {
            merged.encoding = encoding
        }

        set(merged, serverID: serverID)

        let customPrefs = ServerPlaybackFactsSync.customPrefs(for: merged)

        for (id, existing) in stored where ServerPlaybackFactsSync.needsWrite(stored: existing, facts: merged) {
            do {
                try await LighterCopyStore.postCustomPrefs(customPrefs, userID: id, client: client, preferencesID: preferencesID)
            } catch {
                logger.warning("Unable to share the server facts with user \(id): \(error.localizedDescription)")
            }
        }

        return merged
    }

    /// The encoding setup and system info. Needs an administrator.
    private static func fetchEncodingFacts(client: JellyfinClient) async -> ServerEncodingFacts? {
        guard let data = try? await client.send(Paths.getNamedConfiguration(key: "encoding")).value,
              let configuration = try? JSONDecoder().decode(EncodingConfigurationDTO.self, from: data)
        else { return nil }

        let systemInfo = try? await client.send(Paths.getSystemInfo).value

        return ServerEncodingFacts(configuration: configuration, systemInfo: systemInfo, now: .now)
    }

    // MARK: - Cache

    private func set(_ facts: ServerPlaybackFacts, serverID: String) {
        factsByServerID[serverID] = facts
        saveCache()
    }

    private func loadCache() {
        guard let data = UserDefaults.appSuite.data(forKey: Self.cacheKey),
              let cached = try? AudienceWatchlistSync.makeDecoder().decode([String: ServerPlaybackFacts].self, from: data)
        else { return }

        factsByServerID = cached
    }

    private func saveCache() {
        guard let data = try? AudienceWatchlistSync.makeEncoder().encode(factsByServerID) else { return }

        UserDefaults.appSuite.set(data, forKey: Self.cacheKey)
    }
}
