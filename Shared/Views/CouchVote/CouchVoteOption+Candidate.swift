//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

extension CouchVoteOption {

    /// Maps a decider card to a vote option.
    ///
    /// - Title: the movie or show name. For an episode, the show name
    ///   (the episode name alone means little on a phone).
    /// - Subtitle: `2019 · 1h 52m`, or `S2:E5 · 42m` for an episode.
    init(candidate: CouchDeciderCandidate, item: BaseItemDto?) {
        let kind: String = switch candidate.kind {
        case .movie: "movie"
        case .series: "series"
        case .episode: "episode"
        }

        var title = candidate.title
        var parts: [String] = []

        if candidate.kind == .episode {
            if let seriesName = item?.seriesName, seriesName.isNotEmpty {
                title = seriesName
            }

            if let locator = item?.seasonEpisodeLabel ?? item?.episodeLocator {
                parts.append(locator)
            }
        } else if let year = candidate.year ?? item?.productionYear {
            parts.append(String(year))
        }

        if let runtime = Self.runtimeLabel(seconds: candidate.runtime) {
            parts.append(runtime)
        }

        self.init(
            id: candidate.id,
            title: title,
            subtitle: parts.isEmpty ? nil : parts.joined(separator: " · "),
            kind: kind
        )
    }

    /// `1h 52m` / `42m`, or `nil` for an unknown or zero runtime.
    private static func runtimeLabel(seconds: TimeInterval?) -> String? {
        guard let seconds, seconds >= 60 else { return nil }

        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.hour, .minute]

        return formatter.string(from: seconds)
    }
}
