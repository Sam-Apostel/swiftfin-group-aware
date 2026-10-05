//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

// MARK: - MemberStatus

extension CouchVoteHostView {

    /// What the host knows about one couch member during a vote.
    enum MemberStatus: Hashable {

        /// Their vote is in (from their phone or cast on the TV).
        case voted
        /// The poll reached their account; they vote on their phone.
        case phone
        /// No phone account (no stored token, or the write failed): they vote on the TV.
        case votesHere
        /// Their phone account stopped answering; they can vote on the TV.
        case unreachable
        /// They are voting in another TV's vote.
        case elsewhere

        var displayTitle: String {
            switch self {
            case .voted:
                L10n.CouchVote.voted
            case .phone:
                L10n.CouchVote.votingOnPhone
            case .votesHere:
                L10n.CouchVote.votesHere
            case .unreachable:
                L10n.CouchVote.unreachable
            case .elsewhere:
                L10n.CouchVote.votingElsewhere
            }
        }

        var systemImage: String {
            switch self {
            case .voted:
                "checkmark.circle.fill"
            case .phone:
                "iphone"
            case .votesHere:
                "tv"
            case .unreachable:
                "exclamationmark.triangle.fill"
            case .elsewhere:
                "arrow.triangle.branch"
            }
        }
    }
}

// MARK: - MemberStrip

extension CouchVoteHostView {

    /// The couch as a row of avatars, each with its vote state.
    struct MemberStrip: View {

        @Default(.accentColor)
        private var accentColor

        let members: [UserState]
        let server: ServerState
        let status: (UserState) -> MemberStatus?

        private var avatarSize: CGFloat {
            UIDevice.isTV ? 90 : 48
        }

        private var badgeSize: CGFloat {
            UIDevice.isTV ? 34 : 20
        }

        private func badgeColor(_ status: MemberStatus) -> Color {
            switch status {
            case .voted:
                accentColor
            case .unreachable:
                .orange
            case .phone, .votesHere, .elsewhere:
                .secondary
            }
        }

        @ViewBuilder
        private func badge(_ status: MemberStatus) -> some View {
            if status == .voted {
                Image(systemName: status.systemImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(accentColor.overlayColor, accentColor)
                    .frame(width: badgeSize, height: badgeSize)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Image(systemName: status.systemImage)
                    .font(.system(size: badgeSize * 0.5, weight: .semibold))
                    .foregroundStyle(badgeColor(status))
                    .frame(width: badgeSize, height: badgeSize)
                    .background(.regularMaterial, in: .circle)
                    .transition(.opacity)
            }
        }

        @ViewBuilder
        private func memberView(_ member: UserState) -> some View {
            let memberStatus = status(member)

            VStack(spacing: UIDevice.isTV ? 10 : 4) {
                UserProfileImage(
                    userID: member.id,
                    source: member.profileImageSource(
                        client: server.client
                    ),
                    pipeline: .Swiftfin.local
                )
                .frame(width: avatarSize, height: avatarSize)
                .overlay(alignment: .bottomTrailing) {
                    if let memberStatus {
                        badge(memberStatus)
                            .offset(x: badgeSize * 0.2, y: badgeSize * 0.1)
                    }
                }

                Text(member.username)
                    .font(UIDevice.isTV ? .callout : .caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                Text(memberStatus?.displayTitle ?? .emptyDash)
                    .font(UIDevice.isTV ? .caption : .caption2)
                    .foregroundStyle(memberStatus == .unreachable ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .isVisible(memberStatus != nil)
                    .contentTransition(.opacity)
            }
            .frame(width: UIDevice.isTV ? 200 : 84)
            .accessibilityElement(children: .combine)
        }

        var body: some View {
            ViewThatFits(in: .horizontal) {
                row

                ScrollView(.horizontal) {
                    row
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            }
            // Never dim the avatars because of an edit mode further up the hierarchy
            .isEditing(false)
        }

        private var row: some View {
            HStack(alignment: .top, spacing: UIDevice.isTV ? 20 : 4) {
                ForEach(members) { member in
                    memberView(member)
                }
            }
        }
    }
}
