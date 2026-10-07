//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import JellyfinAPI
import SwiftUI

/// "Who's it for?": pick the people a movie or show is meant for.
///
/// - iOS: present as a sheet (it sets `[.medium, .large]` detents itself).
/// - tvOS: present as a full-screen cover (`NavigationRoute` `.sheet` routes already are).
///
/// The view dismisses itself after `onSave` / `onRemove`; do the async work in those closures.
struct AudiencePickerView: View {

    @Router
    private var router

    @State
    private var selection: Set<String>

    private let title: String
    private let isExisting: Bool
    private let onSave: (Set<String>) -> Void
    private let onRemove: (() -> Void)?

    private let users: [UserState]
    private let kidIDs: Set<String>
    private let presets: [AudiencePreset]
    private let client: JellyfinClient?

    init(
        title: String,
        initialAudience: Set<String>,
        isExisting: Bool,
        onSave: @escaping (Set<String>) -> Void,
        onRemove: (() -> Void)? = nil
    ) {
        self.title = title
        self.isExisting = isExisting
        self.onSave = onSave
        self.onRemove = onRemove
        self._selection = State(initialValue: initialAudience)

        let userSession = Container.shared.currentUserSession()
        var users: [UserState] = []

        if let userSession {
            users.append(userSession.user)

            for member in userSession.householdSessions() where !users.contains(where: { $0.id == member.user.id }) {
                users.append(member.user)
            }
        }

        let kidIDs = Set(users.filter(\.isKid).map(\.id))
        var couchIDs: Set<String> = []
        if let couch = userSession?.couch, couch.isGroup {
            couchIDs = couch.memberIDs
        }

        self.users = users
        self.kidIDs = kidIDs
        self.client = userSession?.client
        self.presets = AudiencePreset.presets(
            users: users,
            primaryID: userSession?.user.id,
            couchIDs: couchIDs,
            kidIDs: kidIDs,
            recents: AudiencePreset.recentAudiences
        )
    }

    // MARK: - Derived

    private var quickPresets: [AudiencePreset] {
        presets.filter { $0.kind == .quick }
    }

    private var recentPresets: [AudiencePreset] {
        presets.filter { $0.kind == .recent }
    }

    private var sentence: String {
        AudienceLabel.sentence(audience: selection, users: users)
    }

    private var canRemove: Bool {
        isExisting && onRemove != nil
    }

    // MARK: - Actions

    private func toggle(_ user: UserState) {
        UIDevice.impact(.light)
        selection.toggle(value: user.id)
    }

    private func apply(_ preset: AudiencePreset) {
        UIDevice.impact(.light)
        selection = preset.memberIDs
    }

    private func save() {
        guard selection.isNotEmpty else { return }

        let audience = selection
        AudiencePreset.recordRecent(audience)
        UIDevice.feedback(.success)
        onSave(audience)
        router.dismiss()
    }

    private func remove() {
        guard let onRemove else { return }

        UIDevice.feedback(.success)
        onRemove()
        router.dismiss()
    }

    // MARK: - Chips

    @ViewBuilder
    private func chips(_ presets: [AudiencePreset]) -> some View {
        FlowLayout(
            alignment: UIDevice.isTV ? .center : .leading,
            direction: .down,
            spacing: UIDevice.isTV ? 20 : 8,
            lineSpacing: UIDevice.isTV ? 20 : 8,
            minRowLength: 1
        ) {
            ForEach(presets) { preset in
                Button(preset.title, systemImage: preset.systemImage) {
                    apply(preset)
                }
                .isSelected(selection == preset.memberIDs)
            }
        }
        .labelStyle(.leadingIcon)
        .buttonStyle(.capsule(selectionTint: Color.Couchfin.orchid, focusTint: UIDevice.isTV ? .white : nil))
        .controlSize(UIDevice.isTV ? .large : .regular)
        .focusSection()
    }

    @ViewBuilder
    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(UIDevice.isTV ? .headline : .subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var presetSections: some View {
        if quickPresets.isNotEmpty {
            VStack(alignment: UIDevice.isTV ? .center : .leading, spacing: UIDevice.isTV ? 20 : 8) {
                sectionHeader(L10n.Audience.quickPicks)
                chips(quickPresets)
            }
        }

        if recentPresets.isNotEmpty {
            VStack(alignment: UIDevice.isTV ? .center : .leading, spacing: UIDevice.isTV ? 20 : 8) {
                sectionHeader(L10n.Audience.recentlyUsed)
                chips(recentPresets)
            }
        }
    }

    // MARK: - Members

    @ViewBuilder
    private func memberButton(_ user: UserState) -> some View {
        MemberButton(
            user: user,
            client: client,
            isKid: kidIDs.contains(user.id),
            isSelected: selection.contains(user.id)
        ) {
            toggle(user)
        }
    }

    @ViewBuilder
    private var members: some View {
        if users.isEmpty {
            Text(L10n.Audience.noPeople)
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            #if os(tvOS)
            // Centered when everyone fits, horizontally scrolling otherwise
            ViewThatFits(in: .horizontal) {
                tvOSMemberRow

                ScrollView(.horizontal) {
                    tvOSMemberRow
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            }
            .focusSection()
            #else
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 76, maximum: 110), spacing: EdgeInsets.itemSpacing)],
                spacing: EdgeInsets.itemSpacing * 2
            ) {
                ForEach(users) { user in
                    memberButton(user)
                }
            }
            #endif
        }
    }

    @ViewBuilder
    private var tvOSMemberRow: some View {
        HStack(spacing: EdgeInsets.itemSpacing) {
            ForEach(users) { user in
                memberButton(user)
                    .frame(width: 220)
            }
        }
        .padding(.vertical, 30)
        .edgePadding(.horizontal)
    }

    // MARK: - Buttons

    @ViewBuilder
    private var saveButton: some View {
        Button {
            save()
        } label: {
            Text(isExisting ? L10n.Audience.update : L10n.Audience.save)
                .frame(maxWidth: .infinity)
        }
        .fontWeight(.semibold)
        .backport
        .buttonStyle(.glassProminent.shadow(false))
        .tint(Color.Couchfin.orchid)
        #if os(iOS)
        .controlSize(.large)
        #endif
        .frame(height: UIDevice.isTV ? 75 : 50)
        .frame(maxWidth: UIDevice.isTV ? 500 : .infinity)
        .disabled(selection.isEmpty)
    }

    @ViewBuilder
    private var removeButton: some View {
        if canRemove {
            Button(role: .destructive) {
                remove()
            } label: {
                Label(L10n.Audience.removeFromWatchlist, systemImage: "bookmark.slash")
                    .frame(maxWidth: .infinity)
            }
            .fontWeight(.semibold)
            .foregroundStyle(.red)
            .backport
            .buttonStyle(.glass)
            #if os(iOS)
            .controlSize(.large)
            #endif
            .frame(height: UIDevice.isTV ? 75 : 50)
            .frame(maxWidth: UIDevice.isTV ? 500 : .infinity)
        }
    }

    @ViewBuilder
    private var sentenceView: some View {
        Text(sentence)
            .font(UIDevice.isTV ? .title3 : .headline)
            .fontWeight(.semibold)
            .foregroundStyle(selection.isEmpty ? HierarchicalShapeStyle.secondary : HierarchicalShapeStyle.primary)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .contentTransition(.opacity)
            .animation(.linear(duration: 0.15), value: selection)
    }

    // MARK: - Layout

    #if os(iOS)
    @ViewBuilder
    private var iOSContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(title)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .lineLimit(2)

                presetSections

                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader(L10n.Audience.people)
                    members
                }
            }
            .edgePadding(.horizontal)
            .padding(.vertical, 16)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                sentenceView
                saveButton
                removeButton
            }
            .edgePadding(.horizontal)
            .padding(.vertical, 12)
            .background(.bar)
        }
    }
    #endif

    #if os(tvOS)
    @ViewBuilder
    private var tvOSContent: some View {
        ScrollView(.vertical) {
            VStack(spacing: 50) {
                VStack(spacing: 10) {
                    Text(L10n.Audience.whosItFor)
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                presetSections

                members

                VStack(spacing: 30) {
                    sentenceView

                    HStack(spacing: 40) {
                        saveButton
                        removeButton
                    }
                    .focusSection()
                }
            }
            .padding(.vertical, 60)
            .frame(maxWidth: .infinity)
        }
        .scrollClipDisabled()
    }
    #endif

    var body: some View {
        Group {
            #if os(tvOS)
            tvOSContent
            #else
            iOSContent
                .navigationTitle(L10n.Audience.whosItFor)
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarCloseButton {
                    router.dismiss()
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            #endif
        }
        .animation(.linear(duration: 0.1), value: selection)
    }
}

// MARK: - MemberButton

extension AudiencePickerView {

    /// An avatar that toggles a person, with the accent checkmark and a kid badge.
    /// Mirrors `UserButton`, without its delete semantics.
    struct MemberButton: View {

        let user: UserState
        let client: JellyfinClient?
        let isKid: Bool
        let isSelected: Bool
        let action: () -> Void

        private var badgeSize: CGFloat {
            UIDevice.isTV ? 56 : 26
        }

        @ViewBuilder
        private var avatar: some View {
            if let client {
                UserProfileImage(
                    userID: user.id,
                    source: user.profileImageSource(client: client),
                    pipeline: .Swiftfin.local
                )
            } else {
                UserProfileImage(
                    userID: user.id,
                    source: ImageSource(),
                    pipeline: .Swiftfin.local
                )
            }
        }

        @ViewBuilder
        private var imageView: some View {
            avatar
                .isEditing(true)
                .isSelected(isSelected)
                .hoverEffect(.highlight)
                .overlay(alignment: .bottomTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: badgeSize, height: badgeSize)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(Color.Couchfin.abyss, Color.Couchfin.bloom)
                            .shadow(radius: 4)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
                .overlay(alignment: .topLeading) {
                    if isKid {
                        // Same badge as the couch picker
                        Image(systemName: "figure.child")
                            .font(UIDevice.isTV ? .title3 : .caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .frame(width: badgeSize * 0.9, height: badgeSize * 0.9)
                            .background(Color.orange, in: .circle)
                            .shadow(radius: 4)
                            .accessibilityLabel(L10n.Audience.kid)
                    }
                }
        }

        @ViewBuilder
        private var titleView: some View {
            Text(user.username)
                .font(UIDevice.isTV ? .headline : .footnote)
                .fontWeight(.semibold)
                .foregroundStyle(isSelected ? HierarchicalShapeStyle.primary : HierarchicalShapeStyle.secondary)
                .lineLimit(1)
        }

        @ViewBuilder
        private var labelView: some View {
            // tvOS breaks HoverEffects when using a VStack
            #if os(tvOS)
            imageView

            titleView
            #else
            VStack(spacing: 6) {
                imageView

                titleView
            }
            #endif
        }

        var body: some View {
            Button(action: action) {
                labelView
            }
            .foregroundStyle(.primary, .secondary)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            #if os(tvOS)
            .buttonStyle(.borderless)
            .buttonBorderShape(.circle)
            #else
            .buttonStyle(.plain)
            #endif
        }
    }
}
