//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

extension SeerrMediaDetailView {

    /// Sheet for requesting a show: "All seasons" or individual seasons.
    struct SeasonRequestView: View {

        @Default(.accentColor)
        private var accentColor

        @Environment(\.dismiss)
        private var dismiss

        @State
        private var selection: Set<Int>

        let title: String
        let seasons: [SeerrSeason]
        /// `nil` requests all seasons.
        let onRequest: ([Int]?) -> Void

        init(
            title: String,
            seasons: [SeerrSeason],
            onRequest: @escaping ([Int]?) -> Void
        ) {
            self.title = title
            self.seasons = seasons
            self.onRequest = onRequest
            self._selection = State(initialValue: Set(seasons.map(\.seasonNumber)))
        }

        private var isAllSelected: Bool {
            seasons.allSatisfy { selection.contains($0.seasonNumber) }
        }

        private var allSeasonsBinding: Binding<Bool> {
            Binding(
                get: { isAllSelected },
                set: { isOn in
                    selection = isOn ? Set(seasons.map(\.seasonNumber)) : []
                }
            )
        }

        private func binding(for seasonNumber: Int) -> Binding<Bool> {
            Binding(
                get: { selection.contains(seasonNumber) },
                set: { isOn in
                    if isOn {
                        selection.insert(seasonNumber)
                    } else {
                        selection.remove(seasonNumber)
                    }
                }
            )
        }

        private var requestTitle: String {
            isAllSelected ? L10n.SeerrDetail.request : L10n.SeerrDetail.requestSeasonCount(selection.count)
        }

        private func request() {
            onRequest(isAllSelected ? nil : selection.sorted())
            dismiss()
        }

        // MARK: - Views

        @ViewBuilder
        private func seasonRow(_ season: SeerrSeason) -> some View {
            Toggle(isOn: binding(for: season.seasonNumber)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(season.name?.nilIfBlank ?? L10n.SeerrDetail.seasonNumber(season.seasonNumber))

                    if let episodeCount = season.episodeCount {
                        Text(L10n.SeerrDetail.episodeCount(episodeCount))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }

        @ViewBuilder
        private var requestButton: some View {
            Button(action: request) {
                Text(requestTitle)
                    .frame(maxWidth: .infinity)
            }
            .listRowInsets(.zero)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .fontWeight(.semibold)
            .backport
            .buttonStyle(.glassProminent.shadow(false))
            .tint(accentColor)
            .controlSize(.large)
            .disabled(selection.isEmpty)
        }

        var body: some View {
            NavigationStack {
                Form {
                    Section {
                        Toggle(L10n.SeerrDetail.allSeasons, isOn: allSeasonsBinding)
                    }

                    Section {
                        ForEach(seasons, id: \.seasonNumber) { season in
                            seasonRow(season)
                        }
                    } footer: {
                        Text(L10n.SeerrDetail.seasonsFooter)
                    }

                    Section {
                        requestButton
                    }
                }
                .tint(accentColor)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarCloseButton {
                    dismiss()
                }
            }
        }
    }
}
