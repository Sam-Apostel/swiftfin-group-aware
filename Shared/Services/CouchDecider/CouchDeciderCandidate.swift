//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// One title the couch could watch tonight, as the decider deck sees it.
///
/// Foundation only: the deck, the filters and their tests don't need the Jellyfin SDK.
/// The matching `BaseItemDto` (posters, overview, playback) is in `CouchDeciderPool.items`.
struct CouchDeciderCandidate: Hashable, Identifiable, Sendable {

    enum Kind: String, Hashable, Sendable {

        /// A movie, or a standalone video.
        case movie

        /// A whole show. Watching it plays the next-up (or first) episode.
        case series

        /// One episode, usually from "Next up together". It plays right away.
        case episode
    }

    /// Where a candidate comes from on the couch home.
    enum Source: String, CaseIterable, Hashable, Sendable {

        /// "Picked for …": tagged for exactly this couch.
        case picked

        /// "Next up together".
        case nextUp

        /// "New for all of you".
        case newForEveryone

        /// How strongly this source pulls a candidate to the front of the deck.
        var weight: Double {
            switch self {
            case .picked:
                3
            case .nextUp:
                2
            case .newForEveryone:
                1
            }
        }
    }

    /// The Jellyfin item id.
    let id: String

    /// The title shown on the card. For an episode, this is its show's name.
    let title: String

    let kind: Kind

    /// The runtime in seconds, or `nil` when unknown.
    ///
    /// For a show, this is Jellyfin's typical episode runtime.
    let runtime: TimeInterval?

    let genres: [String]

    let year: Int?

    var sources: Set<Source>

    /// The sum of the weights of the candidate's sources.
    var weight: Double {
        sources.reduce(0) { $0 + $1.weight }
    }
}
