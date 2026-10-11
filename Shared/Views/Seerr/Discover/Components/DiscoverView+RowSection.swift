//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension DiscoverView {

    /// A horizontal poster row in the house style; the header opens the paged "see all" grid.
    struct RowSection: View {

        private enum FocusSection {
            case header
            case content
        }

        #if os(tvOS)
        /// Mirrors `PosterHStackLibrarySection`'s header on tvOS.
        private struct HeaderButtonStyle: ButtonStyle {

            func makeBody(configuration: Configuration) -> some View {
                configuration.label
                    .scaleEffect(configuration.isPressed ? 0.97 : 1)
                    .opacity(configuration.isPressed ? 0.8 : 1)
                    .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            }
        }
        #endif

        @FocusState
        private var focusedSection: FocusSection?

        @Router
        private var router

        let row: DiscoverViewModel.Row

        private func routeToLibrary() {
            router.route(to: .library(library: SeerrDiscoverLibrary(category: row.category)))
        }

        #if os(tvOS)
        private var isHeaderFocused: Bool {
            focusedSection == .header
        }
        #endif

        private var header: some View {
            Button(action: routeToLibrary) {
                #if os(tvOS)
                HStack(spacing: 3) {
                    Text(row.category.displayTitle)
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .lineLimit(1)

                    if isHeaderFocused {
                        Image(systemName: "chevron.forward")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .backport
                .glassEffect(
                    isHeaderFocused ? .regular : .identity,
                    in: .capsule
                )
                .animation(.easeInOut(duration: 0.15), value: isHeaderFocused)
                .offset(x: -16)
                #else
                HStack(spacing: 3) {
                    Text(row.category.displayTitle)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .lineLimit(1)

                    Image(systemName: "chevron.forward")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                #endif
            }
            .foregroundStyle(.primary, .secondary)
            .accessibilityAction(named: Text(L10n.openLibrary), routeToLibrary)
            #if os(tvOS)
            .buttonStyle(HeaderButtonStyle())
            #endif
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        var body: some View {
            ContentGroupSection {
                PosterHStack(
                    elements: row.items,
                    displayType: .portrait,
                    size: .small
                ) { media, namespace in
                    media.libraryDidSelectElement(router: router, in: namespace)
                }
                .focusSection()
                .focused($focusedSection, equals: .content)
            } header: {
                header
                    .focusSection()
                    .focused($focusedSection, equals: .header)
                    .edgePadding(.horizontal)
                    .accessibilityAddTraits(.isHeader)
            }
            .focusSection()
            .defaultFocus(
                $focusedSection,
                .content,
                priority: .userInitiated
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel(row.category.displayTitle)
        }
    }
}
