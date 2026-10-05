//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// The one client-side allowlist of official ratings that are fine for a child. Foundation only.
///
/// Used as a fallback where the server's parental rating can't help (the decider)
/// and for Seerr certifications. It fails closed: anything unknown, `nil` or empty is not kid-safe.
enum KidRatings {

    /// The normalized ratings that are fine for a child.
    ///
    /// - US: Approved, G, TV-G, TV-Y, TV-Y7, PG, TV-PG
    /// - GB: U
    /// - NL / BE: AL, KT, MG6, 6
    /// - FR: Tous
    /// - DE: FSK 0, FSK 6 (normalized to 0 and 6)
    static let allowed: Set<String> = [
        "APPROVED",
        "G",
        "TV-G",
        "TV-Y",
        "TV-Y7",
        "PG",
        "TV-PG",
        "U",
        "AL",
        "KT",
        "TOUS",
        "MG6",
        "0",
        "6",
    ]

    /// Country prefixes that are stripped, e.g. `NL-6`, `US-PG`, `nl/AL`.
    private static let countryPrefixes = ["US", "NL", "BE", "DE", "GB"]

    private static let prefixSeparators: Set<Character> = ["-", "/", ":"]

    /// Whether an official rating or certification is fine for a child.
    static func isKidSafe(_ rating: String?) -> Bool {
        guard let rating else { return false }

        let normalized = normalized(rating)

        guard normalized.isEmpty == false else { return false }

        return allowed.contains(normalized)
    }

    /// Trims, uppercases, strips a country prefix and an `FSK` prefix,
    /// and maps content-descriptor variants (`TV-PG-V`, `TV-Y7-FV`) to their base rating.
    static func normalized(_ rating: String) -> String {
        var value = rating
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        value = strippingCountryPrefix(value)
        value = strippingFSKPrefix(value)

        if value.hasPrefix("TV-PG-") {
            return "TV-PG"
        }

        if value.hasPrefix("TV-Y7-") {
            return "TV-Y7"
        }

        return value
    }

    private static func strippingCountryPrefix(_ value: String) -> String {
        for prefix in countryPrefixes where value.hasPrefix(prefix) {
            let rest = value.dropFirst(prefix.count)

            guard let separator = rest.first, prefixSeparators.contains(separator) else { continue }

            return String(rest.dropFirst())
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return value
    }

    /// `FSK-6`, `FSK 6` and `FSK6` become `6`.
    private static func strippingFSKPrefix(_ value: String) -> String {
        guard value.hasPrefix("FSK") else { return value }

        var rest = Substring(value.dropFirst(3))

        while let first = rest.first, first == "-" || first == " " || first == ":" {
            rest = rest.dropFirst()
        }

        return String(rest)
    }
}
