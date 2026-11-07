//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import SwiftUI

/// The AI's unsure guesses, one yes/no at a time. Answers are kept across scans.
struct UniverseReviewsView: View {

    @InjectedObject(\.universeService)
    private var service: UniverseService

    @State
    private var error: Error?
    @State
    private var answering: Set<String> = []

    var body: some View {
        ZStack {
            if service.reviews.isEmpty {
                FinEmptyView(L10n.Universes.reviewEmpty, description: L10n.Universes.reviewEmptyDescription) {
                    EmptyView()
                }
            } else {
                List {
                    ForEach(service.reviews) { review in
                        row(review)
                    }
                }
            }
        }
        .animation(.default, value: service.reviews)
        .navigationTitle(L10n.Universes.reviewTitle)
        .toolbarTitleDisplayMode(.inline)
        .refreshable {
            await service.refreshOverview(force: true)
        }
        .task {
            await service.refreshOverview(force: true)
        }
        .errorMessage($error)
    }

    private func image(for review: UniverseReview) -> ImageSource? {
        review.entry.jellyfinItemId.flatMap(UniverseCollage.posterSource(itemID:))
            ?? review.entry.imageUrl.map { ImageSource(url: $0) }
    }

    private func row(_ review: UniverseReview) -> some View {
        HStack(spacing: UIDevice.isTV ? 30 : 14) {
            ImageView(image(for: review))
                .placeholder { _ in
                    Color.secondarySystemFill
                }
                .failure {
                    Image(systemName: review.entry.kind.systemImage)
                        .foregroundStyle(.secondary)
                }
                .aspectRatio(16 / 9, contentMode: .fill)
                .frame(width: UIDevice.isTV ? 220 : 110)
                .clipShape(.rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(review.question)
                    .font(.headline)

                if let reason = review.reason {
                    Text(reason)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    Button(L10n.Universes.yes, systemImage: "checkmark") {
                        answer(review, accept: true)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(L10n.Universes.no, systemImage: "xmark") {
                        answer(review, accept: false)
                    }
                    .buttonStyle(.bordered)
                }
                .disabled(answering.contains(review.id))
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 6)
    }

    private func answer(_ review: UniverseReview, accept: Bool) {
        answering.insert(review.id)
        Task { @MainActor in
            defer { answering.remove(review.id) }
            do {
                try await service.answer(review, accept: accept)
                UIDevice.feedback(.success)
            } catch {
                self.error = error
            }
        }
    }
}
