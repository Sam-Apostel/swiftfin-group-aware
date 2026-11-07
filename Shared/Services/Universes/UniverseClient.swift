//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

enum UniverseError: LocalizedError {

    case unauthorized
    case server(status: Int)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            L10n.Universes.errorUnauthorized
        case let .server(status):
            L10n.Universes.errorServer(status)
        case .decoding:
            L10n.Universes.errorDecoding
        }
    }
}

/// The Universes companion app's API (`/api/v1`), signed in with the person's Jellyfin token.
struct UniverseClient: Sendable {

    let baseURL: URL
    let accessToken: String

    private static let session = URLSession(configuration: .swiftfin)

    /// The port the Universes Umbrel app listens on.
    static let defaultPort = 7457

    // MARK: - Requests

    func status() async throws -> UniverseServiceStatus {
        try await get("status")
    }

    func universes() async throws -> [UniverseSummary] {
        let list: UniverseList = try await get("universes")
        return list.universes
    }

    func universe(id: String) async throws -> Universe {
        try await get("universes/\(id)")
    }

    /// The universes an item belongs to. Pass the series id for an episode as `alsoIDs`.
    func universes(forItemID itemID: String, alsoIDs: [String] = []) async throws -> [UniverseSummary] {
        let query = alsoIDs.map { URLQueryItem(name: "alsoId", value: $0) }
        let list: UniverseList = try await get("items/\(itemID)/universes", query: query)
        return list.universes
    }

    func reviews() async throws -> [UniverseReview] {
        let list: UniverseReviewList = try await get("reviews")
        return list.reviews
    }

    func answer(reviewID: String, accept: Bool) async throws {
        try await post("reviews/\(reviewID)", body: ["decision": accept ? "accept" : "reject"])
    }

    func answer(universeID: String, entryID: String, accept: Bool) async throws {
        try await post(
            "universes/\(universeID)/entries/\(entryID)/decision",
            body: ["decision": accept ? "accept" : "reject"]
        )
    }

    func scan() async throws {
        try await post("scan", body: [:])
    }

    // MARK: - Discovery

    /// Whether a Universes app answers at `baseURL`. Doesn't need a token.
    static func ping(_ baseURL: URL, timeout: TimeInterval = 4) async -> Bool {
        var request = URLRequest(url: baseURL.appending(path: "api/v1/ping"))
        request.timeoutInterval = timeout

        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }

        return body["service"] as? String == "couchfin-universes"
    }

    /// Where the Universes app usually is: the Jellyfin host on the Umbrel app's port.
    static func candidateURLs(near jellyfinURL: URL) -> [URL] {
        guard let host = jellyfinURL.host() else { return [] }

        return ["http", "https"].compactMap { scheme in
            var components = URLComponents()
            components.scheme = scheme
            components.host = host
            components.port = defaultPort
            return components.url
        }
    }

    // MARK: - Plumbing

    /// `path` is plain text: `appending(path:)` percent-encodes it (ids never contain "/").
    private func request(_ path: String, query: [URLQueryItem] = []) -> URLRequest {
        var url = baseURL.appending(path: "api/v1/").appending(path: path, directoryHint: .notDirectory)
        if query.isNotEmpty {
            url.append(queryItems: query)
        }

        var request = URLRequest(url: url)
        request.setValue(accessToken, forHTTPHeaderField: "X-Emby-Token")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func get<Value: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> Value {
        let (data, response) = try await Self.session.data(for: request(path, query: query))
        try Self.check(response)

        do {
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            throw UniverseError.decoding(String(describing: error))
        }
    }

    private func post(_ path: String, body: [String: String]) async throws {
        var request = request(path)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await Self.session.data(for: request)
        try Self.check(response)
    }

    private static func check(_ response: URLResponse) throws {
        guard let status = (response as? HTTPURLResponse)?.statusCode else { return }

        if status == 401 || status == 403 {
            throw UniverseError.unauthorized
        }
        guard (200 ..< 300).contains(status) else {
            throw UniverseError.server(status: status)
        }
    }
}
