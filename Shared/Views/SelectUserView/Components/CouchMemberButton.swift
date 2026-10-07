//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension SelectUserView {

    /// A user avatar that toggles the user on or off the couch.
    ///
    /// Copies the `UserButton` look and its accent checkmark, but drives
    /// selection from the couch selection and not from the delete-mode selection.
    struct CouchMemberButton: View {

        let user: UserState
        let server: ServerState
        let showServer: Bool
        let isSelected: Bool
        let isDimmed: Bool
        let isKid: Bool
        let action: () -> Void
        let onToggleKid: () -> Void
        let onDelete: () -> Void

        private var checkmarkSize: CGFloat {
            UIDevice.isTV ? 75 : 40
        }

        private var titleForegroundStyle: HierarchicalShapeStyle {
            isDimmed ? .secondary : .primary
        }

        private var subtitle: String? {
            switch (isKid, showServer) {
            case (true, true):
                "\(L10n.CouchPicker.kid) · \(server.name)"
            case (true, false):
                L10n.CouchPicker.kid
            case (false, true):
                server.name
            case (false, false):
                nil
            }
        }

        var body: some View {
            Button(action: action) {
                labelView
            }
            .contextMenu {
                Button(
                    isKid ? L10n.CouchPicker.unmarkAsKid : L10n.CouchPicker.markAsKid,
                    systemImage: "figure.child",
                    action: onToggleKid
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
            .overlay {
                // On the couch: the avatar lights up with the fin's rim.
                if isSelected {
                    Circle()
                        .strokeBorder(
                            AngularGradient(colors: Color.Couchfin.rimColors + [Color.Couchfin.bio], center: .center),
                            lineWidth: UIDevice.isTV ? 8 : 4
                        )
                        .shadow(color: Color.Couchfin.glint.opacity(0.6), radius: UIDevice.isTV ? 18 : 10)
                        .transition(.opacity)
                }
            }
            .hoverEffect(.highlight)
            .overlay(alignment: .bottomTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: checkmarkSize, height: checkmarkSize)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.Couchfin.abyss, Color.Couchfin.glint)
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
                .foregroundStyle(.white)
                .frame(width: checkmarkSize * 0.8, height: checkmarkSize * 0.8)
                .background(Color.orange, in: .circle)
                .shadow(radius: 4)
                .hoverEffect(.lift)
                .accessibilityLabel(L10n.CouchPicker.kid)
        }

        @ViewBuilder
        private var titleView: some View {
            Text(user.username)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(titleForegroundStyle)
                .lineLimit(1)

            AlternateLayoutView {
                // Setting the subtitle here ensures that we reserve the horizonal spacing
                // swiftlint:disable:next hard_coded_display_string
                Text(subtitle ?? "Hidden")
                    .lineLimit(1)
            } content: {
                if let subtitle {
                    Marquee(subtitle)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.footnote)
        }
    }
}
