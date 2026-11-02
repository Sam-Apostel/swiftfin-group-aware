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

extension DiscoverView {

    /// Entry card to "Coming up", with the next thing that drops.
    struct ComingUpCard: View {

        @Default(.accentColor)
        private var accentColor

        @InjectedObject(\.releaseCalendarService)
        private var service: ReleaseCalendarService

        @Router
        private var router

        private var subtitle: String {
            guard let next = service.entries.first else {
                return L10n.ReleaseCalendar.cardEmpty
            }

            let day = ReleaseCalendarDay.title(for: next.date).lowercased()
            return L10n.ReleaseCalendar.cardNext(title: next.title, day: day)
        }

        private var icon: some View {
            Image(systemName: "calendar")
                .font(.title3)
                .foregroundStyle(accentColor.overlayColor)
                .frame(width: UIDevice.isTV ? 70 : 44, height: UIDevice.isTV ? 70 : 44)
                .background(accentColor, in: .circle)
        }

        private var label: some View {
            HStack(spacing: UIDevice.isTV ? 24 : 12) {
                icon

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.ReleaseCalendar.title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.forward")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }

        var body: some View {
            button
                .accessibilityElement(children: .combine)
                .task {
                    await service.refresh()
                }
        }

        #if os(tvOS)
        private var button: some View {
            Button {
                router.route(to: .releaseCalendar)
            } label: {
                label
                    .padding(24)
            }
            .buttonStyle(.card)
        }
        #else
        private var button: some View {
            Button {
                router.route(to: .releaseCalendar)
            } label: {
                label
                    .padding(12)
                    .background {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.secondarySystemBackground)
                    }
                    .contentShape(.rect(cornerRadius: 16))
            }
            .buttonStyle(.plain)
        }
        #endif
    }
}
