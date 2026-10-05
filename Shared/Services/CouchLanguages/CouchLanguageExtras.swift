//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

// Foundation only: this file is type-checked and unit-tested on Linux.

/// Couch-only language facts about a person that Jellyfin can't express.
///
/// Cached per user in `StoredValues`, and synced through that person's own DisplayPreferences row
/// `swiftfin-couch-languages` (client `swiftfin-couch`), key `sgw.lang.v1`. The newest `updatedAt` wins.
struct CouchLanguageExtras: Codable, Hashable, Sendable {

    /// Languages understood besides the Jellyfin audio language (any code; canonicalised when saved).
    var alsoUnderstands: [String] = []
    /// Subtitle languages read besides the Jellyfin subtitle language and the understood languages.
    var alsoReads: [String] = []
    /// `nil` = derive: kids don't read subtitles, everyone else does.
    var readsSubtitles: Bool? = nil
    /// `true` → the three fields below replace the Jellyfin preferences on the couch.
    ///
    /// Used when the person's Jellyfin configuration can't be written from this device.
    var overridesJellyfin: Bool = false
    var audioLanguage: String? = nil
    var subtitleLanguage: String? = nil
    var subtitleMode: CouchSubtitleMode? = nil
    var updatedAt: Date = .distantPast

    static let displayPreferencesID = "swiftfin-couch-languages"
    /// The custom prefs key; its value is the JSON of this struct, with ISO-8601 dates.
    static let customPrefsKey = "sgw.lang.v1"

    /// The JSON stored under `customPrefsKey`.
    func encodedForCustomPrefs() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Self.iso8601String(from: date))
        }

        guard let data = try? encoder.encode(self) else { return nil }

        return String(data: data, encoding: .utf8)
    }

    /// Decodes the value stored under `customPrefsKey`. `nil` for a missing or unreadable value.
    static func decode(customPrefsValue: String?) -> CouchLanguageExtras? {
        guard let data = customPrefsValue?.data(using: .utf8), data.isEmpty == false else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            guard let date = Self.date(fromISO8601: value) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid ISO-8601 date: \(value)"
                )
            }

            return date
        }

        return try? decoder.decode(CouchLanguageExtras.self, from: data)
    }
}

// MARK: - Codable

extension CouchLanguageExtras {

    private enum CodingKeys: String, CodingKey {
        case alsoUnderstands
        case alsoReads
        case readsSubtitles
        case overridesJellyfin
        case audioLanguage
        case subtitleLanguage
        case subtitleMode
        case updatedAt
    }

    /// Lenient: missing keys keep their defaults, an unknown subtitle mode is ignored.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.alsoUnderstands = try container.decodeIfPresent([String].self, forKey: .alsoUnderstands) ?? []
        self.alsoReads = try container.decodeIfPresent([String].self, forKey: .alsoReads) ?? []
        self.readsSubtitles = try container.decodeIfPresent(Bool.self, forKey: .readsSubtitles)
        self.overridesJellyfin = try container.decodeIfPresent(Bool.self, forKey: .overridesJellyfin) ?? false
        self.audioLanguage = try container.decodeIfPresent(String.self, forKey: .audioLanguage)
        self.subtitleLanguage = try container.decodeIfPresent(String.self, forKey: .subtitleLanguage)
        self.subtitleMode = (try? container.decodeIfPresent(String.self, forKey: .subtitleMode))
            .flatMap(\.self)
            .flatMap(CouchSubtitleMode.init(rawValue:))
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
    }
}

// MARK: - Sync helpers

extension CouchLanguageExtras {

    /// Which copy wins when the local cache and the synced row differ.
    enum SyncWinner: Equatable {
        /// Both copies say the same thing (or there is nothing to sync).
        case same
        /// Keep the local copy and write it to the server.
        case local
        /// Replace the local copy with the server's.
        case remote
    }

    /// Dates closer than this are the same save (the synced copy keeps millisecond precision).
    static let sameSaveTolerance: TimeInterval = 0.01

    /// The newest `updatedAt` wins. On the same save time the server copy wins, so devices converge.
    static func syncWinner(local: CouchLanguageExtras, remote: CouchLanguageExtras?) -> SyncWinner {
        guard let remote else {
            // Never saved here either: nothing to write.
            return local.updatedAt > .distantPast ? .local : .same
        }

        let delta = local.updatedAt.timeIntervalSince(remote.updatedAt)

        if abs(delta) < sameSaveTolerance {
            return local.hasSameContent(as: remote) ? .same : .remote
        }

        return delta > 0 ? .local : .remote
    }

    /// Equal apart from `updatedAt`.
    func hasSameContent(as other: CouchLanguageExtras) -> Bool {
        var lhs = self
        var rhs = other
        lhs.updatedAt = .distantPast
        rhs.updatedAt = .distantPast
        return lhs == rhs
    }

    /// The language lists canonicalised and de-duplicated. The override fields are kept as entered.
    func normalized() -> CouchLanguageExtras {
        var copy = self
        copy.alsoUnderstands = CouchLanguageCode.unique(alsoUnderstands.map(\.self))
        copy.alsoReads = CouchLanguageCode.unique(alsoReads.map(\.self))
        return copy
    }

    /// `now`, rounded to whole milliseconds so it survives the ISO-8601 round trip.
    static func saveDate(_ now: Date = .now) -> Date {
        Date(timeIntervalSince1970: (now.timeIntervalSince1970 * 1000).rounded() / 1000)
    }

    // MARK: ISO-8601

    private static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func date(fromISO8601 value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let date = formatter.date(from: value) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
