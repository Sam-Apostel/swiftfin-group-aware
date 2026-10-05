//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

// MARK: - JSONDecoder

extension JSONDecoder {

    /// A decoder for Seerr responses.
    ///
    /// Seerr entity timestamps use fractional seconds (`2020-09-12T10:00:27.000Z`),
    /// which `.iso8601` cannot parse. TMDB dates (`releaseDate`, `firstAirDate`) are
    /// date-only strings and are always decoded as `String`.
    static func seerr() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()

            // Values written by a default `JSONEncoder` (`.deferredToDate`), e.g. when a model was persisted
            if let interval = try? container.decode(Double.self) {
                return Date(timeIntervalSinceReferenceDate: interval)
            }

            let string = try container.decode(String.self)

            if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(string) {
                return date
            }

            if let date = try? Date.ISO8601FormatStyle().parse(string) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid Seerr date: \(string)"
            )
        }
        return decoder
    }
}

extension JSONEncoder {

    /// An encoder that writes dates in the same format Seerr sends them,
    /// so encoded Seerr models decode again with `JSONDecoder.seerr()`.
    static func seerr() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(date))
        }
        return encoder
    }
}

// MARK: - Lenient decoding

/// Decodes an element, or swallows the error and stores `nil`.
///
/// Used so a single malformed or unsupported element (a person or
/// collection in search results) does not fail a whole response.
struct SeerrLossy<Element: Decodable>: Decodable {

    let value: Element?

    init(from decoder: Decoder) throws {
        self.value = try? decoder.singleValueContainer().decode(Element.self)
    }
}

extension KeyedDecodingContainer {

    /// Decodes a value, returning `nil` when the key is missing, `null`, or has an unexpected type.
    func decodeLeniently<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        try? decodeIfPresent(type, forKey: key)
    }

    /// Decodes an array, dropping elements that fail to decode.
    ///
    /// Returns `nil` when the key is missing, `null`, or not an array.
    func decodeLossyArray<T: Decodable>(_ type: T.Type, forKey key: Key) -> [T]? {
        guard let elements = try? decodeIfPresent([SeerrLossy<T>].self, forKey: key) else {
            return nil
        }

        return elements.compactMap(\.value)
    }

    /// Decodes a string, returning `nil` for missing, `null`, blank, or non-string values.
    func decodeNonBlankString(forKey key: Key) -> String? {
        guard let string = decodeLeniently(String.self, forKey: key) else {
            return nil
        }

        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
