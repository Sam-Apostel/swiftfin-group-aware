//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import FactoryKit
import SwiftUI

/// The "What should we watch?" button on Home ("What should I watch?" when watching alone),
/// with the couch's status at a glance (`CouchStatus`).
///
/// - iOS: a full-width glass card, with a caption below it on a group couch: who's on the couch,
///   "Browsing as Tuur (kid-safe)" and "Hiding what anyone watched". The caption opens the couch switcher.
/// - tvOS: directly below the cinematic hero, a focusable card, with a compact status card next to it
///   in the same focus section that opens the couch switcher. The switcher asks a grown-up for any change
///   that loosens kid protection, so this is no way around it.
/// - Both: a chip for each member whose account couldn't be checked (`CouchMemberHealth`).
///   "Lisa needs to sign in again" opens sign-in for her, and the couch is signed in again afterwards
///   (`CouchSignInAgain`). The chips clear after the next successful refresh.
struct CouchDeciderEntryGroup: ContentGroup {

    let couch: CouchGroup
    let id: String = "couch-decider"

    func body(with viewModel: Empty) -> Body {
        Body(couch: couch)
    }

    struct Body: View {

        @Default(.accentColor)
        private var accentColor
        @Default(.Couch.lastMemberIDs)
        private var lastMemberIDs
        @Default(.Couch.hideWatchedByAnyMember)
        private var hideWatchedByAnyMember

        @Environment(\.dynamicTypeSize)
        private var dynamicTypeSize

        @InjectedObject(\.couchMemberHealth)
        private var memberHealth: CouchMemberHealth
        @InjectedObject(\.userSessionManager)
        private var userSessionManager: UserSessionManager

        @Router
        private var router

        @ScaledMetric(relativeTo: .headline)
        private var scaledIconSize: CGFloat = 48

        let couch: CouchGroup

        // MARK: - Values

        private var iconSize: CGFloat {
            UIDevice.isTV ? 90 : min(scaledIconSize, 72)
        }

        private var server: ServerState? {
            userSessionManager.currentSession?.server
        }

        private var title: String {
            couch.isGroup ? L10n.CouchDecider.whatShouldWeWatch : L10n.CouchHomeStatus.whatShouldIWatch
        }

        private var subtitle: String {
            couch.isGroup
                ? L10n.CouchDecider.letCouchfinPick(couch.displayNames)
                : L10n.CouchHomeStatus.letCouchfinPickForYou
        }

        /// iOS wraps the title at accessibility text sizes instead of truncating it. tvOS is unchanged.
        private var titleLineLimit: Int {
            !UIDevice.isTV && dynamicTypeSize.isAccessibilitySize ? 2 : 1
        }

        private var subtitleLineLimit: Int {
            UIDevice.isTV ? 1 : 2
        }

        private var statusHeadline: String {
            CouchStatus.headline(couch: couch, lastMemberIDs: lastMemberIDs)
        }

        private var isHidingWatched: Bool {
            CouchStatus.isHidingWatched(couch: couch, hideWatchedByAnyMember: hideWatchedByAnyMember)
        }

        private var memberIssues: [CouchStatus.MemberIssue] {
            CouchStatus.memberIssues(couch: couch, failures: memberHealth.failures)
        }

        // MARK: - Body

        var body: some View {
            VStack(alignment: .leading, spacing: UIDevice.isTV ? 24 : 10) {
                #if os(tvOS)
                HStack(spacing: 40) {
                    deciderButton

                    statusButton
                }
                #else
                deciderButton

                if couch.isGroup {
                    statusCaption
                }
                #endif

                if memberIssues.isNotEmpty {
                    memberIssueChips
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .edgePadding(.horizontal)
            .focusSection()
        }

        // MARK: - Decider card

        private var deciderButton: some View {
            Button {
                router.route(to: .couchDecider(couch: couch))
            } label: {
                deciderLabel
            }
            .foregroundStyle(.primary, .secondary)
            #if os(tvOS)
            .buttonStyle(.card)
            #else
            .buttonStyle(.plain)
            #endif
            .accessibilityLabel(title)
            .accessibilityHint(subtitle)
        }

        @ViewBuilder
        private var deciderLabel: some View {
            HStack(spacing: UIDevice.isTV ? 32 : 14) {
                icon

                VStack(alignment: .leading, spacing: UIDevice.isTV ? 6 : 2) {
                    Text(title)
                        .font(UIDevice.isTV ? .title3 : .headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .lineLimit(titleLineLimit)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(subtitle)
                        .font(UIDevice.isTV ? .callout : .subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(subtitleLineLimit)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.forward")
                    .font(UIDevice.isTV ? .title3 : .body)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
            .padding(UIDevice.isTV ? 32 : 14)
            #if os(tvOS)
            .frame(width: 960, alignment: .leading)
            #else
            .frame(maxWidth: .infinity, alignment: .leading)
            #endif
            #if os(iOS)
            .backport
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            #endif
        }

        private var icon: some View {
            Image(systemName: "dice.fill")
                .font(.system(size: iconSize * 0.48, weight: .semibold))
                .foregroundStyle(accentColor.overlayColor)
                .frame(width: iconSize, height: iconSize)
                .background(accentColor, in: .circle)
                .accessibilityHidden(true)
        }

        // MARK: - Status

        /// tvOS: who's on the couch, next to the decider card. Opens the couch switcher.
        private var statusButton: some View {
            Button {
                router.route(to: .couchSwitcher)
            } label: {
                HStack(spacing: 24) {
                    avatars(size: 72)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(statusHeadline)
                            .font(.callout)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        if isHidingWatched {
                            Label(L10n.CouchHomeStatus.hidingWatched, systemImage: "eye.slash")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(32)
                .frame(maxWidth: .infinity, minHeight: 154, alignment: .leading)
            }
            #if os(tvOS)
            .buttonStyle(.card)
            #else
                .buttonStyle(.plain)
            #endif
            .accessibilityHint(L10n.CouchSwitcher.changeWhosOnTheCouch)
        }

        /// iOS: who's on the couch, below the decider card. Opens the couch switcher.
        private var statusCaption: some View {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    router.route(to: .couchSwitcher)
                } label: {
                    HStack(spacing: 8) {
                        avatars(size: 24)

                        Text(statusHeadline)
                            .font(.footnote)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)

                        Spacer(minLength: 0)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint(L10n.CouchSwitcher.changeWhosOnTheCouch)

                if isHidingWatched {
                    statusChip(
                        L10n.CouchHomeStatus.hidingWatched,
                        systemImage: "eye.slash",
                        tint: .secondary
                    )
                }
            }
        }

        @ViewBuilder
        private func avatars(size: CGFloat) -> some View {
            if let server {
                CouchAvatarStack(
                    users: couch.members,
                    server: server,
                    size: size
                )
            }
        }

        // MARK: - Member health

        private var memberIssueChips: some View {
            FlowLayout(
                alignment: .leading,
                direction: .down,
                spacing: UIDevice.isTV ? 20 : 8,
                lineSpacing: UIDevice.isTV ? 20 : 8,
                minRowLength: 1
            ) {
                ForEach(memberIssues) { issue in
                    if issue.canSignInAgain {
                        signInAgainButton(issue)
                    } else {
                        statusChip(issue.message, systemImage: issue.systemImage, tint: .orange)
                    }
                }
            }
        }

        /// "Lisa needs to sign in again": opens sign-in with her name filled in.
        private func signInAgainButton(_ issue: CouchStatus.MemberIssue) -> some View {
            Button {
                signInAgain(issue.member)
            } label: {
                Label(issue.message, systemImage: issue.systemImage)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .labelStyle(.leadingIcon)
            .buttonStyle(.capsule(focusTint: UIDevice.isTV ? .white : nil))
            .controlSize(UIDevice.isTV ? .large : .regular)
            .tint(.orange)
            .accessibilityHint(L10n.CouchHomeStatus.signInAgainHint(issue.member.username))
        }

        /// A static chip, e.g. "Hiding what anyone watched" or "Couldn't check Lisa — …".
        private func statusChip(_ text: String, systemImage: String, tint: Color) -> some View {
            Label(text, systemImage: systemImage)
                .font(UIDevice.isTV ? .callout : .footnote)
                .fontWeight(.semibold)
                .foregroundStyle(tint)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, UIDevice.isTV ? 16 : 10)
                .padding(.vertical, UIDevice.isTV ? 8 : 5)
                .background(tint.opacity(0.15), in: Capsule())
        }

        // MARK: - Actions

        private func signInAgain(_ member: UserState) {
            guard let server else { return }

            UIDevice.impact(.light)
            CouchSignInAgain.shared.willSignInAgain(userID: member.id)
            router.route(to: .userSignIn(server: server, username: member.username))
        }
    }
}
