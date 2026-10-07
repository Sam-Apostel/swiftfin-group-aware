//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension SelectUserView {

    /// One-tap chips for saved couches ("Date night") and the last couches, shown above the avatars.
    ///
    /// Tapping a chip puts its people on the couch; tapping the selected chip again starts watching.
    /// Long-press a saved couch to edit or delete it, or a last couch to save or forget it.
    struct CouchPresetChips: View {

        let chips: [CouchChip]
        let selectedMemberIDs: Set<String>
        let userItems: [UserItem]
        let onSelect: (CouchChip) -> Void
        let onEdit: (CouchChip) -> Void
        let onDelete: (CouchChip) -> Void
        let onSave: (CouchChip) -> Void
        let onForget: (CouchChip) -> Void

        private var spacing: CGFloat {
            UIDevice.isTV ? 24 : 8
        }

        private var avatarSize: CGFloat {
            UIDevice.isTV ? 40 : 22
        }

        private var usersByID: [String: UserItem] {
            Dictionary(userItems.map { ($0.user.id, $0) }) { first, _ in first }
        }

        private func isSelected(_ chip: CouchChip) -> Bool {
            selectedMemberIDs.isNotEmpty && selectedMemberIDs == chip.memberSet
        }

        private func title(for chip: CouchChip) -> String {
            if let name = chip.preset?.name, name.isNotEmpty {
                return name
            }

            return L10n.Audience.joinedNames(chip.memberNames)
        }

        var body: some View {
            // Centered when every chip fits, horizontally scrolling otherwise
            ViewThatFits(in: .horizontal) {
                row

                ScrollView(.horizontal) {
                    row
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            }
            .buttonStyle(.capsule(selectionTint: Color.Couchfin.orchid, focusTint: UIDevice.isTV ? .white : nil))
            .controlSize(UIDevice.isTV ? .large : .regular)
            .focusSection()
            .accessibilityElement(children: .contain)
            .accessibilityLabel(L10n.CouchPresets.savedCouches)
        }

        @ViewBuilder
        private var row: some View {
            HStack(spacing: spacing) {
                ForEach(chips) { chip in
                    chipButton(chip)
                }
            }
            // Room for the focus scale and shadow on tvOS
            .padding(.vertical, UIDevice.isTV ? 20 : 4)
            .edgePadding(.horizontal)
        }

        @ViewBuilder
        private func chipButton(_ chip: CouchChip) -> some View {
            let selected = isSelected(chip)

            Button {
                onSelect(chip)
            } label: {
                chipLabel(chip, isSelected: selected)
            }
            .isSelected(selected)
            .contextMenu {
                contextMenuContent(chip)
            }
            .accessibilityLabel(title(for: chip))
            .accessibilityHint(selected ? L10n.CouchPresets.startHint : L10n.CouchPresets.selectHint)
        }

        @ViewBuilder
        private func contextMenuContent(_ chip: CouchChip) -> some View {
            switch chip.kind {
            case .preset:
                Button(L10n.CouchPresets.editCouch, systemImage: "pencil") {
                    onEdit(chip)
                }

                Button(L10n.delete, systemImage: "trash", role: .destructive) {
                    onDelete(chip)
                }

            case .recent:
                Button(L10n.CouchPresets.saveThisCouch, systemImage: "bookmark") {
                    onSave(chip)
                }

                Button(L10n.CouchPresets.forget, systemImage: "xmark.circle", role: .destructive) {
                    onForget(chip)
                }
            }
        }

        @ViewBuilder
        private func chipLabel(_ chip: CouchChip, isSelected: Bool) -> some View {
            HStack(spacing: UIDevice.isTV ? 12 : 6) {
                leadingView(chip)

                Text(title(for: chip))

                if isSelected {
                    Image(systemName: "play.fill")
                        .font(UIDevice.isTV ? .callout : .caption)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .lineLimit(1)
            .fixedSize()
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)
        }

        @ViewBuilder
        private func leadingView(_ chip: CouchChip) -> some View {
            if let emoji = chip.preset?.emoji {
                Text(emoji)
            } else if chip.kind == .preset {
                Image(systemName: "sofa.fill")
            } else {
                avatarStack(chip)
            }
        }

        @ViewBuilder
        private func avatarStack(_ chip: CouchChip) -> some View {
            let items = chip.memberIDs.compactMap { usersByID[$0] }

            if let server = items.first?.server {
                CouchAvatarStack(
                    users: items.map(\.user),
                    server: server,
                    size: avatarSize
                )
            } else {
                Image(systemName: "clock.arrow.circlepath")
            }
        }
    }
}
