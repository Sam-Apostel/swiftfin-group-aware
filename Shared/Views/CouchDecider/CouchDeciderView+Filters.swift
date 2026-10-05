//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

extension CouchDeciderView {

    /// The chip at the end of the filter row, for the titles hidden with "Not tonight".
    enum HiddenChip: Equatable {

        /// "Undo": brings back the last title, for a few seconds after "Not tonight".
        case undo

        /// "Hidden: 3": brings all of them back.
        case hidden(count: Int)
    }

    /// One horizontal row of capsule chips: length (single), kind (single), genres (multi), Clear,
    /// and the Undo / "Hidden: N" chip.
    ///
    /// A `.focusSection()` on tvOS, so swiping up from the action bar lands here.
    struct FilterBar: View {

        @Default(.accentColor)
        private var accentColor

        let filters: CouchDeciderFilters
        let genreChips: [String]
        var hiddenChip: HiddenChip?
        var onUndo: () -> Void = {}
        var onRestoreHidden: () -> Void = {}
        let onChange: (CouchDeciderFilters) -> Void

        private var chipSpacing: CGFloat {
            UIDevice.isTV ? 20 : 8
        }

        var body: some View {
            ScrollView(.horizontal) {
                HStack(spacing: chipSpacing) {
                    lengthChips

                    separator

                    kindChips

                    if genreChips.isNotEmpty {
                        separator

                        genreChipButtons
                    }

                    if !filters.isDefault {
                        separator

                        clearChip
                    }

                    if let hiddenChip {
                        separator

                        hiddenChipButton(hiddenChip)
                    }
                }
                .padding(.vertical, UIDevice.isTV ? 16 : 4)
                .edgePadding(.horizontal)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .labelStyle(.leadingIcon)
            .buttonStyle(.capsule(selectionTint: accentColor, focusTint: UIDevice.isTV ? .white : nil))
            .controlSize(UIDevice.isTV ? .large : .regular)
            .focusSection()
            .animation(.easeInOut(duration: 0.2), value: genreChips)
            .animation(.easeInOut(duration: 0.2), value: filters.isDefault)
            .animation(.easeInOut(duration: 0.2), value: hiddenChip)
        }

        // MARK: - Chips

        @ViewBuilder
        private var lengthChips: some View {
            ForEach(CouchDeciderFilters.Length.allCases, id: \.self) { length in
                Button {
                    guard filters.length != length else { return }

                    var newFilters = filters
                    newFilters.length = length
                    onChange(newFilters)
                } label: {
                    Text(title(for: length))
                }
                .isSelected(filters.length == length)
                .accessibilityLabel(accessibilityTitle(for: length))
                .accessibilityAddTraits(filters.length == length ? .isSelected : [])
            }
        }

        @ViewBuilder
        private var kindChips: some View {
            ForEach(CouchDeciderFilters.KindFilter.allCases, id: \.self) { kind in
                Button {
                    guard filters.kind != kind else { return }

                    var newFilters = filters
                    newFilters.kind = kind
                    onChange(newFilters)
                } label: {
                    Text(title(for: kind))
                }
                .isSelected(filters.kind == kind)
                .accessibilityAddTraits(filters.kind == kind ? .isSelected : [])
            }
        }

        @ViewBuilder
        private var genreChipButtons: some View {
            ForEach(genreChips, id: \.self) { genre in
                Button {
                    var newFilters = filters

                    if isSelected(genre: genre) {
                        newFilters.genres = filters.genres.filter {
                            $0.caseInsensitiveCompare(genre) != .orderedSame
                        }
                    } else {
                        newFilters.genres.insert(genre)
                    }

                    onChange(newFilters)
                } label: {
                    Text(genre)
                }
                .isSelected(isSelected(genre: genre))
                .accessibilityAddTraits(isSelected(genre: genre) ? .isSelected : [])
            }
        }

        private var clearChip: some View {
            Button {
                onChange(CouchDeciderFilters())
            } label: {
                Label(L10n.CouchDecider.clear, systemImage: "xmark")
            }
            .transition(.opacity.combined(with: .scale))
        }

        /// One button for both states, so tvOS focus stays on it when "Undo" turns into "Hidden: N".
        private func hiddenChipButton(_ chip: HiddenChip) -> some View {
            Button {
                switch chip {
                case .undo:
                    onUndo()
                case .hidden:
                    onRestoreHidden()
                }
            } label: {
                switch chip {
                case .undo:
                    Label(L10n.CouchDecider.undo, systemImage: "arrow.uturn.backward")
                case let .hidden(count):
                    Label(L10n.CouchDecider.hiddenCount(count), systemImage: "eye.slash")
                }
            }
            .id("hidden-chip")
            .accessibilityLabel(hiddenChipAccessibilityLabel(chip))
            .transition(.opacity.combined(with: .scale))
        }

        private func hiddenChipAccessibilityLabel(_ chip: HiddenChip) -> String {
            switch chip {
            case .undo:
                L10n.CouchDecider.undoNotTonight
            case let .hidden(count):
                L10n.CouchDecider.bringBack(count)
            }
        }

        private var separator: some View {
            Capsule()
                .fill(.secondary)
                .frame(width: UIDevice.isTV ? 3 : 1.5, height: UIDevice.isTV ? 36 : 18)
                .opacity(0.5)
                .accessibilityHidden(true)
        }

        // MARK: - Helpers

        private func isSelected(genre: String) -> Bool {
            filters.genres.contains { $0.caseInsensitiveCompare(genre) == .orderedSame }
        }

        private func title(for length: CouchDeciderFilters.Length) -> String {
            switch length {
            case .any:
                L10n.any
            case .underOneHour:
                L10n.CouchDecider.lessThanOneHour
            case .underOneHourFortyFive:
                L10n.CouchDecider.lessThanOneHour45
            case .underTwoHoursThirty:
                L10n.CouchDecider.lessThanTwoHours30
            }
        }

        /// The spoken length: "Under 1 hour 45 minutes" instead of "less than 1h45".
        private func accessibilityTitle(for length: CouchDeciderFilters.Length) -> String {
            switch length {
            case .any:
                L10n.any
            case .underOneHour:
                L10n.CouchDecider.underOneHour
            case .underOneHourFortyFive:
                L10n.CouchDecider.underOneHour45
            case .underTwoHoursThirty:
                L10n.CouchDecider.underTwoHours30
            }
        }

        private func title(for kind: CouchDeciderFilters.KindFilter) -> String {
            switch kind {
            case .all:
                L10n.all
            case .movies:
                L10n.movies
            case .shows:
                L10n.CouchDecider.shows
            }
        }
    }
}
