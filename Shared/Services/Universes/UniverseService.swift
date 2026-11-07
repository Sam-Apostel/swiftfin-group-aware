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
import Logging

extension Container {

    var universeService: Factory<UniverseService> {
        self { @MainActor in UniverseService() }
            .singleton
    }
}

extension Defaults.Keys {

    /// Draw universes with their own type, texture and colours.
    static let universesThemed = Key<Bool>("universesThemed", default: true, suite: .appSuite)
}

/// Finds and talks to the Universes companion app for the current Jellyfin server.
///
/// The app's address is stored per Jellyfin server. Without one, Couchfin looks on the
/// Jellyfin host at the Umbrel app's port, so on umbrelOS it connects by itself.
/// Requests are signed with the current person's Jellyfin token; the app checks it with Jellyfin.
@MainActor
final class UniverseService: ObservableObject {

    @Published
    private(set) var client: UniverseClient?
    @Published
    private(set) var serverURL: URL?
    @Published
    private(set) var isDiscovering = false
    /// Universes and pending reviews, for the Discover card and the settings screen.
    @Published
    private(set) var summaries: [UniverseSummary] = []
    @Published
    private(set) var reviews: [UniverseReview] = []
    @Published
    private(set) var status: UniverseServiceStatus?

    var isConfigured: Bool {
        client != nil
    }

    private let logger = Logger.swiftfin()
    private var cancellables: Set<AnyCancellable> = []
    private var loadedSessionKey: String?
    private var discoveryTask: Task<Void, Never>?
    /// Jellyfin servers where discovery found nothing this launch, so it isn't retried on every screen.
    private var discoveryMisses: Set<String> = []

    private var universeCache: [String: (universe: Universe, at: Date)] = [:]
    private var itemCache: [String: (summaries: [UniverseSummary], at: Date)] = [:]
    private var summariesLoadedAt: Date?

    private static let freshness: TimeInterval = 10 * 60

    init() {
        reload()

        Container.shared
            .userSessionManager()
            .$currentSession
            .map { [$0?.server.id, $0?.user.id] }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.reload()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Configuration

    private var currentSession: UserSession? {
        Container.shared.currentUserSession()
    }

    static func serverURLKey(serverID: String) -> Defaults.Key<String?> {
        Defaults.Key<String?>("universesServerURL_\(serverID.replacing(".", with: "_"))", suite: .appSuite)
    }

    /// Rebuilds the client for the current person and server, discovering the app if needed.
    func reload() {
        guard let session = currentSession else {
            reset()
            loadedSessionKey = nil
            return
        }

        let sessionKey = "\(session.server.id)-\(session.user.id)"
        if sessionKey != loadedSessionKey {
            reset()
            loadedSessionKey = sessionKey
        }

        if let stored = Defaults[Self.serverURLKey(serverID: session.server.id)], let url = URL(string: stored) {
            serverURL = url
            client = UniverseClient(baseURL: url, accessToken: session.user.accessToken)
        } else if !discoveryMisses.contains(session.server.id) {
            discover()
        }
    }

    private func reset() {
        client = nil
        serverURL = nil
        summaries = []
        reviews = []
        status = nil
        universeCache = [:]
        itemCache = [:]
        summariesLoadedAt = nil
    }

    /// Looks for the app next to Jellyfin. Concurrent calls share one search.
    func discover() {
        guard discoveryTask == nil, let session = currentSession else { return }

        let serverID = session.server.id
        let candidates = UniverseClient.candidateURLs(near: session.server.effectiveServerURL)
        isDiscovering = true

        discoveryTask = Task { @MainActor [weak self] in
            var found: URL?
            for candidate in candidates {
                if await UniverseClient.ping(candidate) {
                    found = candidate
                    break
                }
            }

            guard let self else { return }
            self.isDiscovering = false
            self.discoveryTask = nil

            guard let found else {
                self.discoveryMisses.insert(serverID)
                return
            }
            guard self.currentSession?.server.id == serverID else { return }

            self.logger.info("Found Universes", metadata: ["url": .string(found.absoluteString)])
            Defaults[Self.serverURLKey(serverID: serverID)] = found.absoluteString
            self.reload()
        }
    }

    /// Saves an address the person entered, after checking that the app answers there.
    func configure(url: URL) async throws {
        guard let session = currentSession else {
            throw ErrorMessage(L10n.Seerr.errorNoServer)
        }

        let url = url.absoluteString.hasSuffix("/") ? URL(string: String(url.absoluteString.dropLast())) ?? url : url

        guard await UniverseClient.ping(url, timeout: 8) else {
            throw ErrorMessage(L10n.Universes.errorUnreachable)
        }

        // Also checks that the app accepts this Jellyfin sign-in.
        let client = UniverseClient(baseURL: url, accessToken: session.user.accessToken)
        let status = try await client.status()

        Defaults[Self.serverURLKey(serverID: session.server.id)] = url.absoluteString
        discoveryMisses.remove(session.server.id)
        reset()
        serverURL = url
        self.client = client
        self.status = status
    }

    func disconnect() {
        guard let session = currentSession else { return }

        Defaults[Self.serverURLKey(serverID: session.server.id)] = nil
        // Don't immediately find it again: the person chose to disconnect.
        discoveryMisses.insert(session.server.id)
        reset()
    }

    /// Forgets that discovery found nothing, and searches again.
    func rediscover() {
        guard let session = currentSession else { return }

        discoveryMisses.remove(session.server.id)
        Defaults[Self.serverURLKey(serverID: session.server.id)] = nil
        reset()
        discover()
    }

    // MARK: - Data

    func refreshOverview(force: Bool = false) async {
        guard let client else { return }

        if !force, let summariesLoadedAt, Date.now.timeIntervalSince(summariesLoadedAt) < Self.freshness {
            return
        }

        do {
            async let summaries = client.universes()
            async let reviews = client.reviews()
            async let status = client.status()
            self.summaries = try await summaries
            self.reviews = try await reviews
            self.status = try await status
            summariesLoadedAt = .now
        } catch {
            logger.warning("Universes overview failed", metadata: ["error": .string(error.localizedDescription)])
        }
    }

    func universe(id: String, force: Bool = false) async throws -> Universe {
        if !force, let cached = universeCache[id], Date.now.timeIntervalSince(cached.at) < Self.freshness {
            return cached.universe
        }
        guard let client else { throw ErrorMessage(L10n.Universes.notConnectedTitle) }

        let universe = try await client.universe(id: id)
        universeCache[id] = (universe, .now)
        return universe
    }

    /// The universes an item belongs to; empty when the app isn't connected or can't be reached.
    func universes(forItemID itemID: String, alsoIDs: [String] = []) async -> [UniverseSummary] {
        guard let client else { return [] }

        let key = ([itemID] + alsoIDs).joined(separator: ",")
        if let cached = itemCache[key], Date.now.timeIntervalSince(cached.at) < Self.freshness {
            return cached.summaries
        }

        do {
            let summaries = try await client.universes(forItemID: itemID, alsoIDs: alsoIDs)
            itemCache[key] = (summaries, .now)
            return summaries
        } catch {
            logger.debug("Universes for item failed", metadata: ["error": .string(error.localizedDescription)])
            return []
        }
    }

    func answer(_ review: UniverseReview, accept: Bool) async throws {
        guard let client else { return }

        try await client.answer(reviewID: review.id, accept: accept)
        reviews.removeAll { $0.id == review.id }
        universeCache[review.universeId] = nil
        itemCache = [:]
    }

    func answer(universeID: String, entryID: String, accept: Bool) async throws {
        guard let client else { return }

        try await client.answer(universeID: universeID, entryID: entryID, accept: accept)
        reviews.removeAll { $0.universeId == universeID && $0.entry.id == entryID }
        universeCache[universeID] = nil
        itemCache = [:]
    }

    func scan() async throws {
        guard let client else { return }

        try await client.scan()
        status = try? await client.status()
    }
}
