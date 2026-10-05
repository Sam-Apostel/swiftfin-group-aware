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
    ///
    /// The tvOS counterpart of the iOS `SeasonRequestView` (same selection logic),
    /// laid out like a tvOS settings form. Menu dismisses it.
    ///
    /// The Request button comes first and has the default focus, labelled with the count
    /// ("Request 3 seasons"), so requesting everything is one click.
    struct SeasonRequestView: View {

        private enum FocusField: Hashable {
            case request
        }

        @Default(.accentColor)
        private var accentColor

        @Environment(\.dismiss)
        private var dismiss

        @FocusState
        private var focusedField: FocusField?

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
            L10n.SeerrDetail.requestSeasonCount(selection.count)
        }

        private func request() {
            guard selection.isNotEmpty else { return }

            onRequest(isAllSelected ? nil : selection.sorted())
            dismiss()
        }

        // MARK: - Views

        @ViewBuilder
        private var header: some View {
            VStack(spacing: 20) {
                Image(systemName: "tv")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 250)
                    .foregroundStyle(.secondary)

                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)

                Text(L10n.SeerrDetail.requestSeasons)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 500)
        }

        @ViewBuilder
        private func seasonRow(_ season: SeerrSeason) -> some View {
            Toggle(isOn: binding(for: season.seasonNumber)) {
                VStack(alignment: .leading, spacing: 4) {
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
            .fontWeight(.semibold)
            .backport
            .buttonStyle(.glassProminent.shadow(false))
            .tint(accentColor)
            .frame(maxHeight: 75)
            .focused($focusedField, equals: .request)
            .disabled(selection.isEmpty)
        }

        var body: some View {
            Form {
                Section {
                    requestButton
                }

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
            } image: {
                header
            }
            .tint(accentColor)
            .defaultFocus($focusedField, .request, priority: .userInitiated)
        }
    }
}
