//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

@MainActor
protocol ContentGroupProvider: Displayable, Identifiable {

    associatedtype Environment = Empty

    var environment: Environment { get set }
    var id: String { get }

    /// The couch whose "Picked for…" watchlist picks these groups show, or `nil`.
    ///
    /// When set, the groups refresh by themselves when the picks for exactly this couch change,
    /// for example after someone tags a title on another device.
    var picksCouch: CouchGroup? { get }

    /// Whether a full refresh shows the groups as they load instead of waiting for all of them.
    ///
    /// The groups appear in order: only the longest prefix of groups that all finished loading is shown,
    /// so a group never appears above one that is already visible. Defaults to `false`.
    var revealsProgressively: Bool { get }

    @ContentGroupBuilder
    func makeGroups(environment: Environment) async throws -> [any ContentGroup]
}

extension ContentGroupProvider {

    var picksCouch: CouchGroup? {
        nil
    }

    var revealsProgressively: Bool {
        false
    }
}

extension ContentGroupProvider where Environment == Empty {
    var environment: Empty {
        get { .init() }
        set {}
    }
}
