//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

/// Detail screen for a Seerr (TMDB) movie or show: play it when it's in the library,
/// request it otherwise, and tag who it's for.
struct SeerrMediaDetailView: View {

    @Router
    private var router

    @Toaster
    private var toaster

    @State
    private var actionError: Error?
    @State
    private var isPresentingRequestOffer = false
    @State
    private var isPresentingSeasonPicker = false

    @StateObject
    private var viewModel: SeerrMediaDetailViewModel

    init(mediaType: SeerrMediaType, tmdbID: Int) {
        self._viewModel = StateObject(
            wrappedValue: SeerrMediaDetailViewModel(
                mediaType: mediaType,
                tmdbID: tmdbID
            )
        )
    }

    // MARK: - Actions

    private func play(_ item: BaseItemDto) {
        router.route(to: .item(item: item))
    }

    private func request() {
        if viewModel.mediaType == .tv, viewModel.requestableSeasons.isNotEmpty {
            isPresentingSeasonPicker = true
        } else {
            viewModel.requestMedia(seasons: nil)
        }
    }

    private func presentAudiencePicker() {
        guard let details = viewModel.details else { return }

        let viewModel = viewModel
        let onRemove: (() -> Void)? = viewModel.watchlistEntry == nil ? nil : {
            viewModel.removeAudience()
        }

        router.route(
            to: .audiencePicker(
                title: details.title,
                initialAudience: viewModel.suggestedAudience,
                isExisting: viewModel.watchlistEntry != nil,
                onSave: { audience in
                    viewModel.saveAudience(audience)
                },
                onRemove: onRemove
            )
        )
    }

    private func handle(_ event: SeerrMediaDetailViewModel._Event) {
        switch event {
        // The picker already plays the success haptic when it's tapped.
        case .audienceRemoved:
            toaster.present(L10n.SeerrDetail.removedFromWatchlist, systemName: "checkmark.circle.fill")

        case let .audienceSaved(offerRequest):
            if offerRequest {
                // Let the picker sheet finish dismissing before showing the dialog.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(400))
                    isPresentingRequestOffer = true
                }
            } else {
                toaster.present(L10n.SeerrDetail.savedToWatchlist, systemName: "checkmark.circle.fill")
            }

        case let .failed(message):
            actionError = ErrorMessage(message)

        case .requested:
            UIDevice.feedback(.success)
            toaster.present(L10n.SeerrDetail.requestSent, systemName: "checkmark.circle.fill")
        }
    }

    // MARK: - Views

    @ViewBuilder
    private var errorView: some View {
        if viewModel.isSeerrConfigured {
            viewModel.error.map(ErrorView.init)
        } else {
            ContentUnavailableView {
                Label(L10n.SeerrDetail.notConfiguredTitle, systemImage: "popcorn")
            } description: {
                Text(L10n.SeerrDetail.notConfiguredDescription)
            }
        }
    }

    @ViewBuilder
    private var seasonPicker: some View {
        if let details = viewModel.details {
            SeasonRequestView(
                title: details.title,
                seasons: viewModel.requestableSeasons
            ) { seasons in
                viewModel.requestMedia(seasons: seasons)
            }
            .presentationDetents([.medium, .large])
        }
    }

    var body: some View {
        ZStack {
            switch viewModel.state {
            case .content:
                if let details = viewModel.details {
                    ContentView(
                        viewModel: viewModel,
                        details: details,
                        onPlay: play,
                        onRequest: request,
                        onWhoIsItFor: presentAudiencePicker
                    )
                }

            case .error:
                errorView

            case .initial, .refreshing:
                ProgressView()
            }
        }
        .animation(.linear(duration: 0.2), value: viewModel.state)
        .navigationTitle(viewModel.details?.title ?? .empty)
        .toolbarTitleDisplayMode(.inline)
        .refreshable {
            viewModel.background.refresh()
        }
        .onFirstAppear {
            viewModel.refresh()
        }
        .onReceive(viewModel.events) { event in
            handle(event)
        }
        .sheet(isPresented: $isPresentingSeasonPicker) {
            seasonPicker
        }
        .confirmationDialog(
            L10n.SeerrDetail.requestItToo,
            isPresented: $isPresentingRequestOffer,
            titleVisibility: .visible
        ) {
            Button(L10n.SeerrDetail.request) {
                viewModel.requestMedia(seasons: nil)
            }

            Button(L10n.cancel, role: .cancel) {}
        } message: {
            Text(L10n.SeerrDetail.requestItTooMessage)
        }
        .errorMessage($actionError)
    }
}
