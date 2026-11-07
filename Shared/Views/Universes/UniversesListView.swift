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

/// Every universe in the library, grouped by kind: worlds first, backlogs last.
struct UniversesListView: View {

    @Default(.universesThemed)
    private var isThemed

    @InjectedObject(\.universeService)
    private var service: UniverseService

    @Router
    private var router

    @State
    private var isLoaded = false

    private static let kindOrder: [UniverseKind] = [
        .fictionalUniverse, .franchise, .series, .creatorCollab, .nonFiction, .character, .playlist, .other,
    ]

    private struct KindGroup: Identifiable {
        let kind: UniverseKind
        let universes: [UniverseSummary]

        var id: String {
            kind.rawValue
        }
    }

    private var groups: [KindGroup] {
        // Top-level universes only; the rest are one tap away inside their parent.
        let topLevel = service.summaries.filter { summary in
            summary.parentIds.allSatisfy { parentID in !service.summaries.contains { $0.id == parentID } }
        }
        return Self.kindOrder.compactMap { kind in
            let universes = topLevel.filter { $0.kind == kind }
            return universes.isEmpty ? nil : KindGroup(kind: kind, universes: universes)
        }
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: UIDevice.isTV ? 520 : 280), spacing: UIDevice.isTV ? 40 : 14)]
    }

    var body: some View {
        ZStack {
            if !service.isConfigured {
                notConnectedView
            } else if service.summaries.isNotEmpty {
                listView
            } else if !isLoaded {
                ProgressView()
            } else {
                FinEmptyView(L10n.Universes.emptyTitle, description: L10n.Universes.emptyDescription) {
                    EmptyView()
                }
            }
        }
        .navigationTitle(L10n.Universes.title)
        .toolbarTitleDisplayMode(.inline)
        .refreshable {
            await service.refreshOverview(force: true)
        }
        .task {
            await service.refreshOverview()
            isLoaded = true
        }
    }

    private var notConnectedView: some View {
        FinEmptyView(L10n.Universes.notConnectedTitle, description: L10n.Universes.notConnectedDescription) {
            Button {
                router.route(to: .universeSettings)
            } label: {
                Text(L10n.Universes.connect)
                    .frame(maxWidth: .infinity)
            }
            .fontWeight(.semibold)
            .backport
            .buttonStyle(.glassProminent.shadow(false))
            .tint(Color.Couchfin.fin)
            .controlSize(.large)
            .frame(maxWidth: UIDevice.isTV ? 500 : 300)
        }
    }

    private var listView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: UIDevice.isTV ? 50 : 28) {
                if service.reviews.isNotEmpty {
                    Button {
                        router.route(to: .universeReviews)
                    } label: {
                        Label(L10n.Universes.reviewCount(service.reviews.count), systemImage: "questionmark.bubble.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(UIDevice.isTV ? 24 : 14)
                            #if os(iOS)
                            .background(Color.secondarySystemBackground, in: .rect(cornerRadius: 14))
                        #endif
                    }
                    #if os(tvOS)
                    .buttonStyle(.card)
                    #else
                    .buttonStyle(.plain)
                    #endif
                    .edgePadding(.horizontal)
                }

                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: UIDevice.isTV ? 24 : 12) {
                        Label(group.kind.displayTitle, systemImage: group.kind.systemImage)
                            .font(.title2.weight(.bold))
                            .accessibilityAddTraits(.isHeader)
                            .edgePadding(.horizontal)

                        LazyVGrid(columns: columns, alignment: .leading, spacing: UIDevice.isTV ? 40 : 14) {
                            ForEach(group.universes) { universe in
                                Button {
                                    router.route(to: .universe(id: universe.id))
                                } label: {
                                    UniverseSummaryCard(universe: universe, isThemed: isThemed)
                                }
                                #if os(tvOS)
                                .buttonStyle(.card)
                                #else
                                .buttonStyle(.plain)
                                #endif
                            }
                        }
                        .edgePadding(.horizontal)
                    }
                    .focusSection()
                }
            }
            .padding(.vertical, EdgeInsets.edgePadding)
        }
    }
}
