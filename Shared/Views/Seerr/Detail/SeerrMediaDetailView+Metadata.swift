//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension SeerrMediaDetailView {

    /// Year · runtime or seasons · rating · certification.
    struct MetadataHStack: View {

        let details: SeerrMediaDetails
        let year: Int?

        private var ratingText: String? {
            guard let voteAverage = details.voteAverage, voteAverage > 0 else { return nil }

            return voteAverage.formatted(.number.precision(.fractionLength(1)))
        }

        var body: some View {
            DotHStack {
                if let year {
                    Text(String(year))
                }

                if details.mediaType == .movie, let runtimeMinutes = details.runtimeMinutes, runtimeMinutes > 0 {
                    Text(Duration.seconds(runtimeMinutes * 60), format: .hourMinuteAbbreviated)
                }

                if details.mediaType == .tv, let numberOfSeasons = details.numberOfSeasons, numberOfSeasons > 0 {
                    Text(L10n.SeerrDetail.seasonCount(numberOfSeasons))
                }

                if let ratingText {
                    Label {
                        Text(ratingText)
                    } icon: {
                        Image(systemName: "star.fill")
                    }
                    .labelStyle(.attributeBadgeOutline)
                }

                if let certification = details.certification, certification.isNotEmpty {
                    EmptyLabel(certification)
                        .labelStyle(.attributeBadgeOutline)
                }
            }
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
        }
    }

    /// Up to three genres, comma separated.
    struct GenresText: View {

        let details: SeerrMediaDetails

        var body: some View {
            if details.genres.isNotEmpty {
                Text(details.genres.prefix(3).map(\.name).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    /// Available, requested, processing, … as a tinted capsule.
    struct StatusPill: View {

        let status: SeerrMediaDetailStatus

        var body: some View {
            Label(status.displayTitle, systemImage: status.systemImage)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(status.color)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(status.color.opacity(0.2), in: .capsule)
        }
    }
}
