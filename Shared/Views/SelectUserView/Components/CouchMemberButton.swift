//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

extension SelectUserView {

    /// A user avatar that toggles the user on or off the couch.
    ///
    /// Copies the `UserButton` look and its accent checkmark, but drives
    /// selection from the couch selection and not from the delete-mode selection.
    struct CouchMemberButton: View {

        @Default(.accentColor)
        private var accentColor

        let user: UserState
        let server: ServerState
        let showServer: Bool
        let isSelected: Bool
        let isDimmed: Bool
        let isKid: Bool
        let action: () -> Void
        let onToggleKid: () -> Void
        let onDelete: () -> Void
        /// The user has no stored access token: tapping signs them in again
        /// instead of putting them on the couch.
        var needsSignIn: Bool = false
        /// Opens sign-in with the user's name filled in.
        var onSignInAgain: () -> Void = {}
        /// A kid whose server account has no age limit: the badge turns amber
        /// and the subtitle says so, since only this app's filtering protects them.
        var isKidWithoutServerLimit: Bool = false
        /// "Watch as just <name>", the first context-menu item. Hidden when `nil`.
        var onWatchAlone: (() -> Void)?

        /// The kid badge color for a kid without a server age limit.
        static let noAgeLimitColor = Color(red: 1, green: 0.75, blue: 0)

        /// Whether starting asks this user for a PIN (or Face ID).
        private var isLocked: Bool {
            user.accessPolicy != .none
        }

        private var kidSubtitle: String {
            isKidWithoutServerLimit ? L10n.CouchStart.kidNoAgeLimit : L10n.CouchPicker.kid
        }

        private var subtitleColor: Color {
            if needsSignIn {
                return .orange
            }

            return isKid && isKidWithoutServerLimit ? Self.noAgeLimitColor : .secondary
        }

        private var checkmarkSize: CGFloat {
            UIDevice.isTV ? 75 : 40
        }

        private var titleForegroundStyle: HierarchicalShapeStyle {
            isDimmed ? .secondary : .primary
        }

        private var subtitle: String? {
            if needsSignIn {
                return showServer ? "\(L10n.CouchPicker.signInAgain) · \(server.name)" : L10n.CouchPicker.signInAgain
            }

            return switch (isKid, showServer) {
            case (true, true):
                "\(kidSubtitle) · \(server.name)"
            case (true, false):
                kidSubtitle
            case (false, true):
                server.name
            case (false, false):
                nil
            }
        }

        var body: some View {
            // A selected user still toggles off, so they can be taken off the couch
            Button(action: needsSignIn && !isSelected ? onSignInAgain : action) {
                labelView
            }
            .contextMenu {
                if let onWatchAlone, !needsSignIn {
                    Button(
                        L10n.CouchStart.watchAsJust(user.username),
                        systemImage: "person.fill",
                        action: onWatchAlone
                    )
                }

                Button(
                    isKid ? L10n.CouchPicker.unmarkAsKid : L10n.CouchPicker.markAsKid,
                    systemImage: "figure.child",
                    action: onToggleKid
                )

                // For a sign-in that ran out or was revoked by a password change
                Button(
                    L10n.CouchPicker.signInAgain,
                    systemImage: "person.badge.key",
                    action: onSignInAgain
                )

                Button(
                    L10n.delete,
                    systemImage: "trash",
                    role: .destructive,
                    action: onDelete
                )
            }
            .foregroundStyle(.primary, .secondary)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            #if os(tvOS)
            .buttonStyle(.borderless)
            .buttonBorderShape(.circle)
            #endif
        }

        @ViewBuilder
        private var labelView: some View {
            // tvOS breaks HoverEffects when using a VStack
            #if os(tvOS)
            imageView

            titleView
            #else
            VStack {
                imageView

                titleView
            }
            #endif
        }

        @ViewBuilder
        private var imageView: some View {
            // `UserProfileImage` dims itself when editing and not selected
            UserProfileImage(
                userID: user.id,
                source: user.profileImageSource(
                    client: server.client
                ),
                pipeline: .Swiftfin.local
            )
            .isEditing(isDimmed)
            .isSelected(false)
            .hoverEffect(.highlight)
            .overlay(alignment: .bottomTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: checkmarkSize, height: checkmarkSize)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(accentColor.overlayColor, accentColor)
                        .shadow(radius: 4)
                        .transition(.scale.combined(with: .opacity))
                        .hoverEffect(.lift)
                }
            }
            .overlay(alignment: .topLeading) {
                if isKid {
                    kidBadge
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }

        private var kidBadge: some View {
            Image(systemName: "figure.child")
                .font(UIDevice.isTV ? .title3 : .footnote)
                .fontWeight(.bold)
                .foregroundStyle(isKidWithoutServerLimit ? Color.black : Color.white)
                .frame(width: checkmarkSize * 0.8, height: checkmarkSize * 0.8)
                .background(isKidWithoutServerLimit ? Self.noAgeLimitColor : Color.orange, in: .circle)
                .shadow(radius: 4)
                .hoverEffect(.lift)
                .accessibilityLabel(
                    isKidWithoutServerLimit ? L10n.CouchStart.kidNoAgeLimitAccessibilityLabel : L10n.CouchPicker.kid
                )
        }

        @ViewBuilder
        private var titleView: some View {
            HStack(spacing: UIDevice.isTV ? 8 : 4) {
                Text(user.username)
                    .lineLimit(1)

                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(UIDevice.isTV ? .callout : .caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(L10n.CouchStart.locked)
                }
            }
            .font(.headline)
            .fontWeight(.semibold)
            .foregroundStyle(titleForegroundStyle)

            AlternateLayoutView {
                // Setting the subtitle here ensures that we reserve the horizonal spacing
                // swiftlint:disable:next hard_coded_display_string
                Text(subtitle ?? "Hidden")
                    .lineLimit(1)
            } content: {
                if let subtitle {
                    Marquee(subtitle)
                        .foregroundStyle(subtitleColor)
                }
            }
            .font(.footnote)
        }
    }
}

extension View {

    /// Binds the picker's focus to a user, on tvOS, when a binding is given.
    @ViewBuilder
    func couchPickerFocused(_ binding: FocusState<String?>.Binding?, userID: String) -> some View {
        #if os(tvOS)
        if let binding {
            focused(binding, equals: userID)
        } else {
            self
        }
        #else
        self
        #endif
    }
}
