//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension ReleaseCalendarView {

    /// Poster, title, what drops (`S2·E5`, `Digital`) and where it comes from.
    struct EntryRow: View {

        let entry: CalendarEntry
        let action: () -> Void

        private var statusColor: Color {
            switch entry.status {
            case .inLibrary:
                .green
            case .inLibrarySoon:
                Color.Couchfin.glint
            case .requested:
                .orange
            case .onWatchlist:
                Color.Couchfin.bloom
            }
        }

        var body: some View {
            Button(action: action) {
                HStack(alignment: .center, spacing: EdgeInsets.edgePadding) {
                    PosterThumbnail(entry: entry)
                        .subtleShadow()
                        .frame(width: UIDevice.isTV ? 100 : 60)

                    details
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .foregroundStyle(.primary, .secondary)
            .accessibilityElement(children: .combine)
        }

        private var details: some View {
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.title)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                DotHStack {
                    Text(entry.subtitle)

                    if entry.isTimeKnown {
                        Text(entry.date, format: .dateTime.hour().minute())
                    }

                    if let detail = entry.detail {
                        Text(detail)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                Label(entry.statusTitle, systemImage: entry.statusSystemImage)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.15), in: .capsule)
            }
        }
    }

    // MARK: - Poster

    struct PosterThumbnail: View {

        let entry: CalendarEntry

        var body: some View {
            ZStack {
                Rectangle()
                    .fill(.complexSecondary)

                if let imageURL = entry.imageURL {
                    ImageView(imageURL)
                        .image { (image: Image) in
                            image
                                .aspectRatio(contentMode: .fill)
                        }
                        .placeholder { _ in
                            SystemImageContentView(systemName: entry.systemImage)
                        }
                        .failure {
                            SystemImageContentView(systemName: entry.systemImage)
                        }
                } else {
                    SystemImageContentView(systemName: entry.systemImage)
                }
            }
            .posterStyle(.portrait)
        }
    }
}
