//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import UIKit

/// The release notes of this build, bundled by the TestFlight workflow from T-Minus' pending notes
/// (`Shared/Resources/CouchfinWhatsNew.json`, written by `Scripts/CI/tminus.py next`).
///
/// The checked-in file has no notes, so local builds show the empty state and never the sheet.
struct BundledReleaseNotes: Decodable, Equatable {

    struct Note: Decodable, Hashable {

        enum Kind: String, Decodable {
            case new
            case test
        }

        let kind: Kind
        let text: String
    }

    let version: String?
    let build: String?
    let notes: [Note]

    var isEmpty: Bool {
        notes.isEmpty
    }

    var newNotes: [Note] {
        notes.filter { $0.kind == .new }
    }

    var notesToTry: [Note] {
        notes.filter { $0.kind == .test }
    }

    /// "1.4.1 (202611021200)", from the app itself so it always matches what's installed.
    var versionLabel: String? {
        TMinusClient.release
    }

    // MARK: - Loading

    static let current: BundledReleaseNotes? = {
        guard let url = Bundle.main.url(forResource: "CouchfinWhatsNew", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return nil }

        return try? JSONDecoder().decode(BundledReleaseNotes.self, from: data)
    }()

    // MARK: - Shown once per build

    private static let lastShownKey = "whatsNew.lastShownBuild"

    private static var currentBuild: String {
        TMinusClient.release ?? ""
    }

    /// This build's notes, if they haven't been shown yet.
    static var unseen: BundledReleaseNotes? {
        guard let current, current.notes.isNotEmpty else { return nil }
        guard UserDefaults.appSuite.string(forKey: lastShownKey) != currentBuild else { return nil }

        return current
    }

    static func markShown() {
        UserDefaults.appSuite.set(currentBuild, forKey: lastShownKey)
    }
}
