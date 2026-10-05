//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

enum SeerrError: LocalizedError {

    /// No Seerr server is configured for the current Jellyfin server.
    case notConfigured
    /// The API key was rejected (401, or Seerr's `403 { error }` for unauthenticated callers).
    case unauthorized
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
        case .server, .decoding:
            nil
        }
    }

    /// The HTTP status code, if this error came from a response.
    var statusCode: Int? {
        switch self {
        case let .server(status, _):
            status
        case .unauthorized:
            401
        case .notConfigured, .decoding:
            nil
        }
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
