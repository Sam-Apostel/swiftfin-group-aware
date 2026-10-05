//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension SeerrMediaDetailView {

    /// A horizontal row of circular TMDB profile images.
    struct CastSection: View {

        let cast: [SeerrCastMember]

        private var members: [(offset: Int, element: SeerrCastMember)] {
            Array(cast.prefix(20).enumerated())
        }

        var body: some View {
            ContentGroupSection {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: EdgeInsets.itemSpacing) {
                        ForEach(members, id: \.offset) { member in
                            CastMemberView(member: member.element)
                        }
                    }
                    .edgePadding(.horizontal)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            } header: {
                Text(L10n.SeerrDetail.cast)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .edgePadding(.horizontal)
                    .accessibilityAddTraits(.isHeader)
            }
        }
    }

    private struct CastMemberView: View {

        let member: SeerrCastMember

        private let imageSize: CGFloat = 80

        var body: some View {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(.complexSecondary)

                    ImageView(SeerrImage.url(member.profilePath, size: "w185"))
                        .image { (image: Image) in
                            image
                                .aspectRatio(contentMode: .fill)
                        }
                        .placeholder { _ in
                            Color.clear
                        }
                        .failure {
                            SystemImageContentView(systemName: "person.fill", ratio: 0.5)
                        }
                }
                .frame(width: imageSize, height: imageSize)
                .clipShape(Circle())
                .accessibilityHidden(true)

                VStack(spacing: 2) {
                    Text(member.name)
                        .font(.footnote)
                        .fontWeight(.medium)
                        .lineLimit(2)

                    if let character = member.character?.nilIfBlank {
                        Text(character)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .multilineTextAlignment(.center)
            }
            .frame(width: imageSize + 10)
            .accessibilityElement(children: .combine)
        }
    }
}
