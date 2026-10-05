//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum SeerrError: LocalizedError {

    /// No Seerr server is configured for the current Jellyfin server.
    case notConfigured
    /// The API key was rejected (401, or Seerr's `403 { error }` for unauthenticated callers).
    /// Also thrown for anonymous clients (e.g. a Quick Connect request that isn't authorized yet).
    case unauthorized
    /// A person's Seerr session (Jellyfin Quick Connect) was rejected: it ran out or was ended.
    /// Same responses as `unauthorized`, from a session client.
    case sessionExpired
    /// The Seerr server can't be reached: it is off, the address is wrong, or there is no network.
    ///
    /// `host` is the server's host, with the port when there is one (`seerr.local:5055`).
    case unreachable(host: String)
    /// Any other non-2xx response, or a 2xx response carrying only an error message.
    case server(status: Int, message: String?)
    /// The response could not be decoded.
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            L10n.Seerr.errorNotConfigured

        case .unauthorized:
            L10n.Seerr.errorUnauthorized

        case .sessionExpired:
            L10n.Seerr.errorSessionExpired

        case let .unreachable(host):
            L10n.Seerr.errorUnreachable(host)

        case let .server(status, message):
            if let message, message.isEmpty == false {
                message
            } else {
                L10n.Seerr.errorServer(status)
            }

        case .decoding:
            L10n.Seerr.errorDecoding
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .notConfigured:
            L10n.Seerr.errorNotConfiguredSuggestion
        case .unauthorized:
            L10n.Seerr.errorUnauthorizedSuggestion
        case .sessionExpired:
            L10n.Seerr.errorSessionExpiredSuggestion
        case .unreachable:
            L10n.Seerr.errorUnreachableSuggestion
        case .server, .decoding:
            nil
        }
    }

    /// The HTTP status code, if this error came from a response.
    var statusCode: Int? {
        switch self {
        case let .server(status, _):
            status
        case .unauthorized, .sessionExpired:
            401
        case .notConfigured, .unreachable, .decoding:
            nil
        }
    }

    /// Whether Seerr rejected the credentials: the API key, or a person's session.
    var isAuthenticationFailure: Bool {
        switch self {
        case .unauthorized, .sessionExpired:
            true
        case .notConfigured, .unreachable, .server, .decoding:
            false
        }
    }

    /// Whether the Seerr server couldn't be reached at all.
    var isUnreachable: Bool {
        if case .unreachable = self {
            return true
        }
        return false
    }

    /// Whether a `URLError` means the Seerr server can't be reached right now.
    static func isUnreachable(_ error: URLError) -> Bool {
        switch error.code {
        case .cannotConnectToHost, .cannotFindHost, .timedOut, .notConnectedToInternet, .networkConnectionLost:
            true
        default:
            false
        }
    }

    /// The host of a Seerr server URL, with its port, for messages (`seerr.local:5055`).
    static func displayHost(of url: URL) -> String {
        guard let host = url.host, host.isEmpty == false else {
            return url.absoluteString
        }

        if let port = url.port {
            return "\(host):\(port)"
        }

        return host
    }
}

/// Seerr error bodies: `{ message, errors }` from routes, `{ status, error }` from the auth middleware.
struct SeerrErrorBody: Decodable, Sendable {

    let message: String?
    let error: String?

    private enum CodingKeys: String, CodingKey {
        case message
        case error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.message = container.decodeNonBlankString(forKey: .message)
        self.error = container.decodeNonBlankString(forKey: .error)
    }
}
