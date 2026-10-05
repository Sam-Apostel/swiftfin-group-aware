//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import Get

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A client for the Seerr (Jellyseerr / Overseerr) REST API under `<server>/api/v1`.
///
/// A client authenticates in one of two ways (`AuthMode`):
/// - the admin API key (`X-Api-Key`). Calls that act on behalf of a person pass
///   `asUser` (a Seerr user id), sent as `X-Api-User`;
/// - a person's own Seerr session (`connect.sid`), e.g. from Jellyfin Quick Connect.
///
/// - Important: The API key is admin-equivalent and a session cookie is
///   password-equivalent. Both are only added in the `APIClientDelegate`, never
///   stored on requests or logged by this type. Seerr clients never use a cookie
///   jar: cookie storage is turned off and a session is sent as a manual `Cookie`
///   header, so the sessions of different people can't mix.
final class SeerrClient: Sendable {

    /// How a `SeerrClient` authenticates.
    enum AuthMode: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {

        /// The admin API key (`X-Api-Key`).
        ///
        /// With `asUser`, every call acts as that Seerr user (`X-Api-User`)
        /// unless the call passes its own `asUser`.
        case apiKey(String, asUser: Int?)

        /// A Seerr session cookie (the `connect.sid` value), e.g. from Jellyfin Quick Connect.
        ///
        /// The session's user is the caller: `asUser` arguments are ignored.
        case session(cookie: String)

        /// Redacted: never contains the key or the cookie.
        var description: String {
            switch self {
            case let .apiKey(_, asUser):
                if let asUser {
                    "apiKey(<redacted>, asUser: \(asUser))"
                } else {
                    "apiKey(<redacted>)"
                }

            case .session:
                "session(<redacted>)"
            }
        }

        var debugDescription: String {
            description
        }

        /// The `X-Api-User` sent when a call passes no `asUser`.
        var defaultUser: Int? {
            switch self {
            case let .apiKey(_, asUser):
                asUser
            case .session:
                nil
            }
        }

        var isSession: Bool {
            switch self {
            case .apiKey:
                false
            case .session:
                true
            }
        }
    }

    /// The name of Seerr's (express-session) session cookie.
    static let sessionCookieName = "connect.sid"

    /// The Seerr server URL, as configured (no `/api/v1`).
    let baseURL: URL
    /// `baseURL` + `/api/v1`.
    let apiBaseURL: URL
    /// `nil` for an anonymous client: only public endpoints and sign-in work.
    let auth: AuthMode?

    private let apiClient: APIClient
    private let userIDCache = SeerrUserIDCache()

    /// An API key client: `init(baseURL:auth: .apiKey(apiKey, asUser: nil), ...)`.
    ///
    /// - Parameters:
    ///   - baseURL: The Seerr server URL, e.g. `http://192.168.1.10:5055` or `https://example.com/seerr`.
    ///   - apiKey: Settings → General → API Key.
    ///   - sessionConfiguration: Defaults to a 20 second request timeout.
    ///   - sessionDelegate: e.g. a Pulse `URLSessionProxyDelegate` that redacts `X-Api-Key`.
    convenience init(
        baseURL: URL,
        apiKey: String,
        sessionConfiguration: URLSessionConfiguration? = nil,
        sessionDelegate: URLSessionDelegate? = nil
    ) {
        self.init(
            baseURL: baseURL,
            auth: .apiKey(apiKey, asUser: nil),
            sessionConfiguration: sessionConfiguration,
            sessionDelegate: sessionDelegate
        )
    }

    /// - Parameters:
    ///   - baseURL: The Seerr server URL, e.g. `http://192.168.1.10:5055` or `https://example.com/seerr`.
    ///   - auth: The API key or a session cookie; `nil` for public endpoints and sign-in only.
    ///   - sessionConfiguration: Defaults to a 20 second request timeout. Cookie storage is
    ///     turned off on a copy of it.
    ///   - sessionDelegate: e.g. a Pulse `URLSessionProxyDelegate` that redacts `X-Api-Key` and `Cookie`.
    init(
        baseURL: URL,
        auth: AuthMode?,
        sessionConfiguration: URLSessionConfiguration? = nil,
        sessionDelegate: URLSessionDelegate? = nil
    ) {
        let baseURL = SeerrClient.normalizedServerURL(baseURL)
        let apiBaseURL = baseURL.appendingPathComponent("api").appendingPathComponent("v1")

        self.baseURL = baseURL
        self.apiBaseURL = apiBaseURL
        self.auth = auth

        var configuration = APIClient.Configuration(
            baseURL: apiBaseURL,
            sessionConfiguration: SeerrClient.cookielessConfiguration(from: sessionConfiguration),
            delegate: SeerrClientDelegate(auth: auth, apiBaseURL: apiBaseURL)
        )
        configuration.sessionDelegate = sessionDelegate
        configuration.decoder = .seerr()
        configuration.encoder = .seerr()

        self.apiClient = APIClient(configuration: configuration)
    }

    /// A copy of `configuration` (default: a 20 second request timeout) that neither stores nor sends cookies.
    ///
    /// Copied, so a shared configuration like `.swiftfin` is never changed.
    private static func cookielessConfiguration(from configuration: URLSessionConfiguration?) -> URLSessionConfiguration {
        let copy: URLSessionConfiguration

        if let configuration, let configurationCopy = configuration.copy() as? URLSessionConfiguration {
            copy = configurationCopy
        } else {
            copy = URLSessionConfiguration.default
            copy.timeoutIntervalForRequest = 20
        }

        copy.httpCookieStorage = nil
        copy.httpShouldSetCookies = false
        copy.httpCookieAcceptPolicy = .never

        return copy
    }

    // MARK: - Server

    /// `GET /status`. Public; use it to test that the URL points at a Seerr server.
    func status() async throws -> SeerrStatus {
        try await send(Request(path: "/status"))
    }

    /// `GET /auth/me`. Validates the API key (or the `asUser` id), or the session.
    func me(asUser: Int? = nil) async throws -> SeerrUser {
        try await send(Request(path: "/auth/me"), asUser: asUser)
    }

    // MARK: - Quick Connect (Seerr 3.4+, Jellyfin only)

    /// `POST /auth/jellyfin/quickconnect/initiate`. Public.
    ///
    /// Starts a Jellyfin Quick Connect request on Seerr's behalf. Authorize `code` on
    /// Jellyfin (`Paths.authorizeQuickConnect`) as the person signing in, then pass
    /// `secret` to `authenticateQuickConnect(secret:)`.
    ///
    /// - Throws: `SeerrError.server(status: 403, ...)` when Seerr doesn't use Jellyfin,
    ///           `SeerrError.server(status: 500, ...)` when Jellyfin refused (Quick Connect disabled),
    ///           `SeerrError.server(status: 404, ...)` on servers older than 3.4.
    func initiateQuickConnect() async throws -> SeerrQuickConnect {
        try await send(Request(path: "/auth/jellyfin/quickconnect/initiate", method: .post))
    }

    /// `GET /auth/jellyfin/quickconnect/check?secret=`. Public.
    ///
    /// Whether the Quick Connect request was authorized on Jellyfin yet.
    func isQuickConnectAuthorized(secret: String) async throws -> Bool {
        let response: SeerrQuickConnectState = try await send(
            Request(path: "/auth/jellyfin/quickconnect/check", query: [("secret", secret)])
        )
        return response.authenticated ?? false
    }

    /// `POST /auth/jellyfin/quickconnect/authenticate`. Public.
    ///
    /// Signs in with an authorized Quick Connect request and returns the new Seerr
    /// session (`connect.sid`, valid for 30 days) and its user. The cookie is read
    /// from `Set-Cookie`; it is never stored in a cookie jar.
    ///
    /// - Throws: `SeerrError.unauthorized` / `SeerrError.server` when the request is not
    ///           authorized (`INVALID_CREDENTIALS`) or the user may not sign in (`403 Access denied.`).
    func authenticateQuickConnect(secret: String) async throws -> SeerrSignIn {
        let request = Request<SeerrUser>(
            path: "/auth/jellyfin/quickconnect/authenticate",
            method: .post,
            body: SeerrQuickConnectSecretBody(secret: secret)
        )
        let response = try await data(for: request, asUser: nil)
        let user = try decode(SeerrUser.self, from: response.data)

        let setCookie = (response.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Set-Cookie")

        guard let cookie = setCookie.flatMap(SeerrClient.sessionCookie(fromSetCookie:)) else {
            throw SeerrError.server(status: response.statusCode ?? 200, message: L10n.SeerrQuickConnect.errorNoSession)
        }

        return SeerrSignIn(user: user, cookie: cookie)
    }

    /// `POST /auth/logout`: ends this client's session on the server. Does nothing for other auth modes.
    func signOut() async throws {
        guard auth?.isSession == true else { return }

        _ = try await data(for: Request<Void>(path: "/auth/logout", method: .post), asUser: nil)
    }

    /// The `connect.sid` value in a `Set-Cookie` header. Several cookies may be folded into one
    /// header, separated by commas (`Expires` dates also contain commas).
    static func sessionCookie(fromSetCookie header: String) -> String? {
        let prefix = "\(sessionCookieName)="

        for part in header.components(separatedBy: ",") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)

            guard trimmed.hasPrefix(prefix) else { continue }

            let value = trimmed
                .dropFirst(prefix.count)
                .prefix { $0 != ";" }
                .trimmingCharacters(in: .whitespaces)

            if value.isEmpty == false {
                return value
            }
        }

        return nil
    }

    /// Whether a Seerr version (`/status`) supports Jellyfin Quick Connect (3.4.0+).
    ///
    /// Development builds (`develop-<commit>`) and unknown formats are assumed to support it;
    /// `initiateQuickConnect()` then tells for sure.
    static func supportsQuickConnect(version: String) -> Bool {
        let numbers = version
            .trimmingCharacters(in: .whitespaces)
            .drop { $0 == "v" || $0 == "V" }
            .split(separator: ".")
            .map { component in Int(component.prefix { $0.isNumber }) }

        guard numbers.count >= 2, let major = numbers[0], let minor = numbers[1] else {
            return true
        }

        return major > 3 || (major == 3 && minor >= 4)
    }

    // MARK: - Discover

    /// `GET /discover/trending` (movies and TV; persons are dropped).
    func trending(page: Int = 1) async throws -> SeerrPage<SeerrMedia> {
        try await send(Request(path: "/discover/trending", query: [("page", String(page))]))
    }

    /// `GET /discover/movies`, sorted by popularity.
    func popularMovies(page: Int = 1) async throws -> SeerrPage<SeerrMedia> {
        try await send(Request(path: "/discover/movies", query: [("page", String(page))]))
    }

    /// `GET /discover/tv`, sorted by popularity.
    func popularTV(page: Int = 1) async throws -> SeerrPage<SeerrMedia> {
        try await send(Request(path: "/discover/tv", query: [("page", String(page))]))
    }

    /// `GET /discover/movies/upcoming`.
    func upcomingMovies(page: Int = 1) async throws -> SeerrPage<SeerrMedia> {
        try await send(Request(path: "/discover/movies/upcoming", query: [("page", String(page))]))
    }

    /// `GET /discover/tv/upcoming`.
    func upcomingTV(page: Int = 1) async throws -> SeerrPage<SeerrMedia> {
        try await send(Request(path: "/discover/tv/upcoming", query: [("page", String(page))]))
    }

    /// Popular family movies rated PG or lower in the US.
    ///
    /// `GET /discover/movies?genre=10751&certificationCountry=US&certificationLte=PG&sortBy=popularity.desc`
    func familyMovies(page: Int = 1) async throws -> SeerrPage<SeerrMedia> {
        let query: [(String, String?)] = [
            ("page", String(page)),
            ("genre", "10751"),
            ("certificationCountry", "US"),
            ("certificationLte", "PG"),
            ("sortBy", "popularity.desc"),
        ]
        return try await send(Request(path: "/discover/movies", query: query))
    }

    /// `GET /search` (movies and TV; persons and collections are dropped).
    func search(query: String, page: Int = 1) async throws -> SeerrPage<SeerrMedia> {
        try await send(Request(path: "/search", query: [("query", query), ("page", String(page))]))
    }

    // MARK: - Details

    /// `GET /movie/{id}` or `GET /tv/{id}`, normalized.
    ///
    /// Pass `asUser` so `onUserWatchlist` and `mediaInfo.watchlists` reflect that person.
    func details(mediaType: SeerrMediaType, tmdbID: Int, asUser: Int? = nil) async throws -> SeerrMediaDetails {
        switch mediaType {
        case .movie:
            let response: SeerrMovieDetailsResponse = try await send(Request(path: "/movie/\(tmdbID)"), asUser: asUser)
            return SeerrMediaDetails(movie: response)

        case .tv:
            let response: SeerrTVDetailsResponse = try await send(Request(path: "/tv/\(tmdbID)"), asUser: asUser)
            return SeerrMediaDetails(tv: response)
        }
    }

    // MARK: - Requests

    /// `POST /request`, attributed to `asUser` when given.
    ///
    /// For TV, `seasons == nil` requests all seasons (`"all"`). Seasons are ignored for movies.
    ///
    /// - Throws: `SeerrError.server(status: 409, ...)` when the title is already requested,
    ///           `SeerrError.server(status: 202, ...)` when there are no seasons left to request,
    ///           `SeerrError.server(status: 403, ...)` for missing permissions or quota.
    @discardableResult
    func request(
        mediaType: SeerrMediaType,
        tmdbID: Int,
        seasons: [Int]? = nil,
        asUser: Int? = nil
    ) async throws -> SeerrRequest {
        let body = SeerrRequestBody(
            mediaType: mediaType,
            mediaId: tmdbID,
            seasons: mediaType == .tv ? (seasons.map(SeerrRequestBody.Seasons.list) ?? .all) : nil
        )

        let request = Request<SeerrRequest>(path: "/request", method: .post, body: body)
        let response = try await data(for: request, asUser: asUser)

        // Seerr answers `202 { message }` when there is nothing left to request
        if let created = try? decode(SeerrRequest.self, from: response.data) {
            return created
        }

        let errorBody = try? JSONDecoder().decode(SeerrErrorBody.self, from: response.data)

        if let message = errorBody?.message ?? errorBody?.error {
            throw SeerrError.server(status: response.statusCode ?? 200, message: message)
        }

        return try decode(SeerrRequest.self, from: response.data)
    }

    /// `GET /request`, newest first.
    ///
    /// With `asUser`, only that person's requests (`requestedBy`) are returned.
    func requests(take: Int = 20, asUser: Int? = nil) async throws -> [SeerrRequest] {
        var query: [(String, String?)] = [
            ("take", String(take)),
            ("skip", "0"),
            ("sort", "added"),
        ]

        if let asUser {
            query.append(("requestedBy", String(asUser)))
        }

        let response: SeerrResultsResponse<SeerrRequest> = try await send(
            Request(path: "/request", query: query),
            asUser: asUser
        )
        return response.results
    }

    // MARK: - Watchlist

    /// `POST /watchlist` for `asUser`. Already on the watchlist (409) counts as success.
    func addToWatchlist(mediaType: SeerrMediaType, tmdbID: Int, title: String, asUser: Int? = nil) async throws {
        let body = SeerrWatchlistBody(tmdbId: tmdbID, mediaType: mediaType, title: title)
        let request = Request<Void>(path: "/watchlist", method: .post, body: body)

        do {
            _ = try await data(for: request, asUser: asUser)
        } catch let SeerrError.server(status, _) where status == 409 {
            return
        }
    }

    /// `DELETE /watchlist/{tmdbId}?mediaType=` for `asUser`. Not on the watchlist (404) counts as success.
    ///
    /// Falls back to the pre-3.2 form without `mediaType` when the server rejects the parameter.
    func removeFromWatchlist(mediaType: SeerrMediaType, tmdbID: Int, asUser: Int? = nil) async throws {
        let request = Request<Void>(
            path: "/watchlist/\(tmdbID)",
            method: .delete,
            query: [("mediaType", mediaType.rawValue)]
        )

        do {
            _ = try await data(for: request, asUser: asUser)
        } catch let SeerrError.server(status, _) where status == 404 {
            return
        } catch let SeerrError.server(status, _) where status == 400 {
            let legacyRequest = Request<Void>(path: "/watchlist/\(tmdbID)", method: .delete)

            do {
                _ = try await data(for: legacyRequest, asUser: asUser)
            } catch let SeerrError.server(status, _) where status == 404 {
                return
            }
        }
    }

    /// `GET /discover/watchlist`: the Seerr watchlist of `asUser` (20 per page).
    func watchlist(page: Int = 1, asUser: Int? = nil) async throws -> SeerrPage<SeerrWatchlistRow> {
        try await send(Request(path: "/discover/watchlist", query: [("page", String(page))]), asUser: asUser)
    }

    // MARK: - Users

    /// Maps a Jellyfin user id to a Seerr user id, importing the user into Seerr if needed.
    ///
    /// 1. `GET /user/jellyfin/{id}` (Seerr 3.3+)
    /// 2. `GET /user?take=1000`, matching `jellyfinUserId` (case-insensitive, dashes stripped)
    /// 3. `POST /user/import-from-jellyfin` (needs the admin API key)
    ///
    /// Results are cached in memory for the lifetime of this client.
    ///
    /// - Returns: `nil` if the user could not be found or imported.
    func seerrUserID(forJellyfinUserID jellyfinUserID: String) async throws -> Int? {
        let normalizedID = SeerrUser.normalizedJellyfinUserID(jellyfinUserID)

        guard normalizedID.isEmpty == false else { return nil }

        if let cachedID = await userIDCache.value(for: normalizedID) {
            return cachedID
        }

        let userID = try await resolveSeerrUserID(normalizedJellyfinUserID: normalizedID)

        if let userID {
            await userIDCache.set(userID, for: normalizedID)
        }

        return userID
    }

    /// `GET /user?take=`: all Seerr users.
    func users(take: Int = 1000) async throws -> [SeerrUser] {
        let response: SeerrResultsResponse<SeerrUser> = try await send(
            Request(path: "/user", query: [("take", String(take)), ("skip", "0")])
        )
        return response.results
    }

    private func resolveSeerrUserID(normalizedJellyfinUserID normalizedID: String) async throws -> Int? {

        // 1. Direct lookup (3.3+). 404 = not imported; older servers reject the route.
        do {
            let user: SeerrUser = try await send(Request(path: "/user/jellyfin/\(normalizedID)"))
            return user.id
        } catch let error as SeerrError {
            if case .unauthorized = error {
                throw error
            }
        }

        // 2. Scan all users
        if let user = try await users().first(where: { $0.matches(jellyfinUserID: normalizedID) }) {
            return user.id
        }

        // 3. Import. Returns only newly created users.
        let request = Request<[SeerrLossy<SeerrUser>]>(
            path: "/user/import-from-jellyfin",
            method: .post,
            body: SeerrImportUsersBody(jellyfinUserIds: [normalizedID])
        )
        let imported = try await send(request).compactMap(\.value)

        if let user = imported.first(where: { $0.matches(jellyfinUserID: normalizedID) }) {
            return user.id
        }

        // Created concurrently, or stored under a different id format: scan once more
        return try await users().first(where: { $0.matches(jellyfinUserID: normalizedID) })?.id
    }

    // MARK: - Sending

    private func send<Value: Decodable>(_ request: Request<Value>, asUser: Int? = nil) async throws -> Value {
        let response = try await data(for: request, asUser: asUser)
        return try decode(Value.self, from: response.data)
    }

    private func data(for request: Request<some Any>, asUser: Int?) async throws -> Response<Data> {
        var request = request

        // Only the API key can act as someone else; a session always acts as its own user.
        if case .apiKey = auth, let asUser = asUser ?? auth?.defaultUser {
            var headers = request.headers ?? [:]
            headers["X-Api-User"] = String(asUser)
            request.headers = headers
        }

        return try await apiClient.data(for: request)
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        do {
            return try JSONDecoder.seerr().decode(Value.self, from: data)
        } catch {
            throw SeerrError.decoding(SeerrClient.describe(error))
        }
    }

    private static func describe(_ error: Error) -> String {
        guard let error = error as? DecodingError else {
            return error.localizedDescription
        }

        func path(_ context: DecodingError.Context) -> String {
            context.codingPath.map(\.stringValue).joined(separator: ".")
        }

        switch error {
        case let .typeMismatch(type, context):
            return "Type mismatch for \(type) at \(path(context)): \(context.debugDescription)"
        case let .valueNotFound(type, context):
            return "Missing \(type) at \(path(context)): \(context.debugDescription)"
        case let .keyNotFound(key, context):
            return "Missing key \(key.stringValue) at \(path(context))"
        case let .dataCorrupted(context):
            return "Corrupted data at \(path(context)): \(context.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }
}

// MARK: - URL helpers

extension SeerrClient {

    /// Builds a Seerr server URL from user input.
    ///
    /// Accepts `host:port`, adds `http://` when no scheme is given, and strips a
    /// trailing `/` or `/api/v1`. Returns `nil` for non-http(s) or host-less input.
    static func serverURL(from string: String) -> URL? {
        var string = string.trimmingCharacters(in: .whitespacesAndNewlines)

        guard string.isEmpty == false else { return nil }

        if !string.contains("://") {
            string = "http://\(string)"
        }

        guard let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host,
              host.isEmpty == false
        else {
            return nil
        }

        return normalizedServerURL(url)
    }

    /// Strips trailing slashes and a trailing `/api/v1`, plus any query or fragment.
    static func normalizedServerURL(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        var path = components.path

        while path.hasSuffix("/") {
            path.removeLast()
        }

        if path.lowercased().hasSuffix("/api/v1") {
            path.removeLast("/api/v1".count)
        }

        while path.hasSuffix("/") {
            path.removeLast()
        }

        components.path = path
        components.query = nil
        components.fragment = nil

        return components.url ?? url
    }
}

// MARK: - SeerrClientDelegate

/// Adds the API key or the session cookie, encodes query items strictly and maps error responses to `SeerrError`.
private struct SeerrClientDelegate: APIClientDelegate, Sendable {

    /// Seerr rejects query values containing raw reserved characters (`:/?#[]@!$&'()*+,;=`)
    /// with a 400, so only RFC 3986 unreserved characters are left unescaped.
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    let auth: SeerrClient.AuthMode?
    let apiBaseURL: URL

    func client(_ client: APIClient, willSendRequest request: inout URLRequest) async throws {
        switch auth {
        case let .apiKey(apiKey, _):
            request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")

        case let .session(cookie):
            // Accept both the bare value and a whole `connect.sid=<value>` pair
            let pair = cookie.hasPrefix("\(SeerrClient.sessionCookieName)=")
                ? cookie
                : "\(SeerrClient.sessionCookieName)=\(cookie)"
            request.setValue(pair, forHTTPHeaderField: "Cookie")

        case nil:
            break
        }
    }

    func client(_ client: APIClient, makeURLForRequest request: Request<some Any>) throws -> URL? {
        guard let url = request.url else {
            throw URLError(.badURL)
        }

        let absoluteURL: URL = if url.scheme == nil {
            apiBaseURL.appendingPathComponent(url.path)
        } else {
            url
        }

        guard var components = URLComponents(url: absoluteURL, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }

        if let query = request.query, query.isEmpty == false {
            components.percentEncodedQueryItems = query.map { name, value in
                URLQueryItem(
                    name: Self.encode(name),
                    value: value.map(Self.encode)
                )
            }
        }

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        return url
    }

    func client(_ client: APIClient, validateResponse response: HTTPURLResponse, data: Data, task: URLSessionTask) throws {
        let statusCode = response.statusCode

        guard (200 ..< 300).contains(statusCode) == false else { return }

        let body = try? JSONDecoder().decode(SeerrErrorBody.self, from: data)

        // The auth middleware answers `403 { status, error }` for unknown keys or users;
        // route errors (missing permission, quota, ...) use `{ message }`.
        if statusCode == 401 || (statusCode == 403 && body?.message == nil) {
            throw SeerrError.unauthorized
        }

        throw SeerrError.server(status: statusCode, message: body?.message ?? body?.error)
    }

    private static func encode(_ string: String) -> String {
        string.addingPercentEncoding(withAllowedCharacters: unreserved) ?? string
    }
}

// MARK: - Bodies and envelopes

/// `{ pageInfo, results }` from `/user` and `/request`.
private struct SeerrResultsResponse<Element: Decodable>: Decodable {

    let results: [Element]

    private enum CodingKeys: String, CodingKey {
        case results
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.results = container.decodeLossyArray(Element.self, forKey: .results) ?? []
    }
}

private struct SeerrRequestBody: Encodable, Sendable {

    enum Seasons: Encodable, Sendable {
        case all
        case list([Int])

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()

            switch self {
            case .all:
                try container.encode("all")
            case let .list(seasons):
                try container.encode(seasons)
            }
        }
    }

    let mediaType: SeerrMediaType
    let mediaId: Int
    let seasons: Seasons?
    let is4k = false

    private enum CodingKeys: String, CodingKey {
        case mediaType
        case mediaId
        case seasons
        case is4k
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mediaType, forKey: .mediaType)
        try container.encode(mediaId, forKey: .mediaId)
        try container.encodeIfPresent(seasons, forKey: .seasons)
        try container.encode(is4k, forKey: .is4k)
    }
}

private struct SeerrWatchlistBody: Encodable, Sendable {

    let tmdbId: Int
    let mediaType: SeerrMediaType
    let title: String
}

private struct SeerrImportUsersBody: Encodable, Sendable {

    let jellyfinUserIds: [String]
}

private struct SeerrQuickConnectSecretBody: Encodable, Sendable {

    let secret: String
}

/// `{ authenticated }` from `/auth/jellyfin/quickconnect/check`.
private struct SeerrQuickConnectState: Decodable, Sendable {

    let authenticated: Bool?
}

// MARK: - Quick Connect

/// A pending Jellyfin Quick Connect request started by Seerr.
struct SeerrQuickConnect: Decodable, Sendable {

    /// The code to authorize on Jellyfin (`Paths.authorizeQuickConnect(code:)`).
    let code: String
    /// Proves the request to Seerr. Never log it.
    let secret: String
}

/// The result of signing in to Seerr.
struct SeerrSignIn: Sendable, CustomStringConvertible {

    let user: SeerrUser
    /// The `connect.sid` value. Store it in the keychain only, never log it.
    let cookie: String

    /// Redacted: never contains the cookie.
    var description: String {
        "SeerrSignIn(userID: \(user.id))"
    }
}

// MARK: - SeerrUserIDCache

/// Jellyfin user id (normalized) → Seerr user id.
private actor SeerrUserIDCache {

    private var storage: [String: Int] = [:]

    func value(for jellyfinUserID: String) -> Int? {
        storage[jellyfinUserID]
    }

    func set(_ seerrUserID: Int, for jellyfinUserID: String) {
        storage[jellyfinUserID] = seerrUserID
    }
}
