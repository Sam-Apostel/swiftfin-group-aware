//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import SwiftUI

/// "Coming up": what drops in the next 60 days, grouped by day.
struct ReleaseCalendarView: View {

    @InjectedObject(\.releaseCalendarService)
    private var service: ReleaseCalendarService

    @Router
    private var router

    private var days: [ReleaseCalendarDay] {
        ReleaseCalendarDay.group(service.entries)
    }

    private var isWaitingForFirstLoad: Bool {
        service.isLoading || (service.lastLoadDate == nil && service.error == nil)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            if service.entries.isNotEmpty {
                listView
            } else if isWaitingForFirstLoad {
                ProgressView()
            } else if let error = service.error {
                ErrorView(error: error)
            } else {
                emptyView
            }
        }
        .animation(.linear(duration: 0.2), value: service.entries.isEmpty)
        .navigationTitle(L10n.ReleaseCalendar.title)
        .toolbarTitleDisplayMode(.inline)
        .refreshable {
            await service.refresh(force: true)
        }
        .onFirstAppear {
            Task {
                await service.refresh()
            }
        }
    }

    // MARK: - States

    private var emptyView: some View {
        ScrollView {
            VStack(spacing: 40) {
                calendarSyncCard

                FinEmptyView(
                    L10n.ReleaseCalendar.emptyTitle,
                    description: L10n.ReleaseCalendar.emptyDescription
                )
                .frame(maxWidth: .infinity)
            }
            .padding(.top, 80)
        }
    }

    /// iOS keeps the calendar toggle reachable when there's nothing coming up.
    @ViewBuilder
    private var calendarSyncCard: some View {
        #if os(iOS)
        VStack(alignment: .leading, spacing: 8) {
            ReleaseCalendarSyncToggle()
                .padding(12)
                .background {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.secondarySystemBackground)
                }

            Text(L10n.ReleaseCalendar.addToCalendarFooter)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .edgePadding(.horizontal)
        #endif
    }

    // MARK: - List

    private var listView: some View {
        List {
            #if os(iOS)
            Section {
                ReleaseCalendarSyncToggle()
            } footer: {
                Text(L10n.ReleaseCalendar.addToCalendarFooter)
            }
            #endif

            ForEach(days) { day in
                Section {
                    ForEach(day.entries) { entry in
                        EntryRow(entry: entry) {
                            select(entry)
                        }
                    }
                } header: {
                    Text(day.title)
                        .accessibilityAddTraits(.isHeader)
                }
            }
        }
    }

    // MARK: - Routing

    private func select(_ entry: CalendarEntry) {
        switch entry.destination {
        case let .jellyfinItem(id):
            router.route(to: .item(id: id))
        case let .seerr(mediaType, tmdbID):
            router.route(to: .seerrMedia(mediaType: mediaType, tmdbID: tmdbID))
        }
    }
}
