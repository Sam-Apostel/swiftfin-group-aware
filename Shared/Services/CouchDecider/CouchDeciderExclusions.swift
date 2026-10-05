//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import FactoryKit
import Foundation

extension Container {

    var couchDeciderExclusions: Factory<CouchDeciderExclusions> {
        self { @MainActor in CouchDeciderExclusions() }
            .singleton
    }
}

/// The titles a couch said "Not tonight" to, per couch.
///
/// In memory only: the exclusions last until the app is relaunched and aren't synced.
/// They are keyed by `CouchGroup.id`, which doesn't depend on the pick order, so reopening
/// the decider or starting the same couch again keeps tonight's exclusions.
@MainActor
final class CouchDeciderExclusions: ObservableObject {

    /// Excluded item ids, per `CouchGroup.id`.
    @Published
    private(set) var excludedByCouchID: [String: Set<String>] = [:]

    init() {}

    /// The item ids excluded for this couch.
    func excluded(couchID: String) -> Set<String> {
        excludedByCouchID[couchID] ?? []
    }

    /// Hides the item for this couch until the app is relaunched.
    func exclude(itemID: String, couchID: String) {
        guard !excluded(couchID: couchID).contains(itemID) else { return }

        excludedByCouchID[couchID, default: []].insert(itemID)
    }

    /// Brings back every title excluded for this couch.
    func reset(couchID: String) {
        guard excludedByCouchID[couchID] != nil else { return }

        excludedByCouchID[couchID] = nil
    }
}
