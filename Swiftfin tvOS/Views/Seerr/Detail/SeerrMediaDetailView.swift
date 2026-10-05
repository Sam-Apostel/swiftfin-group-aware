//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import JellyfinAPI
import SwiftUI

/// tvOS detail screen for a Seerr (TMDB) movie or show, laid out like the cinematic tvOS item header:
/// play it when it's in the library, request it otherwise (as a grown-up on a kid-safe couch),
/// and tag who it's for, pre-selected with the current couch.
///
/// Every behaviour lives in the shared `SeerrMediaDetailViewModel` (including who a request goes out as,
/// the kid gate and the Quick Connect sign-in before a request). This view adds the layout and the Siri Remote focus.
struct SeerrMediaDetailView: View {

    /// The focusable buttons of the left column.
    enum FocusTarget: Hashable {
        case audience
        case primary
        case requestMore
    }

    @Default(.accentColor)
    private var accentColor

    @Router
    private var router

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

    /// Request and "Request it too?": the season picker for a show, else straight to the view model,
    /// which requests as a grown-up on the couch (signing them in to Seerr first when needed).
    private func request() {
        guard viewModel.requestGate == .allowed,
              viewModel.signingInName == nil,
              !viewModel.background.is(.requesting)
        else { return }

        if viewModel.mediaType == .tv, viewModel.requestableSeasons.isNotEmpty {
            isPresentingSeasonPicker = true
        } else {
            viewModel.submitRequest(seasons: nil)
        }
    }

    /// "Request it too?" → Request: let the dialog finish dismissing before the season picker opens.
    private func requestFromOffer() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            request()
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

    private func refreshIfStale(sinceLastDisappear interval: TimeInterval) {
        guard interval > 60 else { return }

        // A background refresh never leaves `.error`
        if viewModel.state == .error {
            viewModel.refresh()
        } else {
            viewModel.background.refresh()
        }
    }

    // No toasts: `@Toaster` crashes outside the video player (see the iOS detail view).
    // The status capsule and the audience label show the outcome instead.
    private func handle(_ event: SeerrMediaDetailViewModel._Event) {
        switch event {
        case .audienceRemoved, .requested:
            break

        case let .audienceSaved(offerRequest):
            guard offerRequest, viewModel.requestGate == .allowed, viewModel.canRequest else { return }

            // Let the full-screen picker finish dismissing before showing the dialog.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                isPresentingRequestOffer = true
            }

        case let .failed(message):
            actionError = ErrorMessage(message)
        }
    }

    // MARK: - Views

    @ViewBuilder
    private func backdrop(_ details: SeerrMediaDetails) -> some View {
        AlternateLayoutView {
            Color.clear
        } content: {
            ImageView(SeerrImage.url(details.backdropPath, size: "w1280"))
                .failure {
                    Color.black
                }
                .aspectRatio(contentMode: .fill)
        }
        .accessibilityHidden(true)
        .overlay {
            Rectangle()
                .fill(Material.regular)
                .mask(gradient: .linear) {
                    (location: 0.3, opacity: 0)
                    (location: 1, opacity: 1)
                }
        }
    }

    @ViewBuilder
    private func contentView(_ details: SeerrMediaDetails) -> some View {
        ZStack {
            backdrop(details)
                .ignoresSafeArea()

            ScrollView {
                CinematicContentGroupContainer {
                    Header(
                        viewModel: viewModel,
                        details: details,
                        requestingAsName: viewModel.requestingAsName,
                        isRequestBlocked: viewModel.requestGate != .allowed,
                        signingInName: viewModel.signingInName,
                        onPlay: play,
                        onRequest: request,
                        onWhoIsItFor: presentAudiencePicker
                    )
                    .edgePadding(.horizontal)
                    .frame(maxWidth: .infinity)
                    .colorScheme(.dark)
                }
                .edgePadding(.bottom)
            }
            .trackingFrame(for: .scrollView)
            .ignoresSafeArea(.container, edges: .all)
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private var notConfiguredView: some View {
        ContentUnavailableView {
            Label(L10n.SeerrDetail.notConfiguredTitle, systemImage: "popcorn")
        } description: {
            Text(L10n.SeerrDetail.notConfiguredDescription)
        } actions: {
            Button {
                router.route(to: .seerrSettings)
            } label: {
                Text(L10n.connect)
                    .frame(maxWidth: .infinity)
            }
            .fontWeight(.semibold)
            .backport
            .buttonStyle(.glassProminent.shadow(false))
            .tint(accentColor)
            .frame(height: 75)
            .frame(maxWidth: 400)
        }
        .focusSection()
    }

    @ViewBuilder
    private var errorView: some View {
        if viewModel.isSeerrConfigured {
            if let error = viewModel.error {
                // `.refreshable` gives `ErrorView` its focusable Retry button (tvOS has no pull to refresh)
                ErrorView(error: error)
                    .refreshable {
                        await viewModel.refresh()
                    }
            }
        } else {
            notConfiguredView
        }
    }

    @ViewBuilder
    private var seasonPicker: some View {
        if let details = viewModel.details {
            SeasonRequestView(
                title: details.title,
                seasons: viewModel.requestableSeasons
            ) { seasons in
                viewModel.submitRequest(seasons: seasons)
            }
        }
    }

    var body: some View {
        ZStack {
            switch viewModel.state {
            case .content:
                if let details = viewModel.details {
                    contentView(details)
                }

            case .error:
                errorView

            case .initial, .refreshing:
                ProgressView()
            }
        }
        .animation(.linear(duration: 0.2), value: viewModel.state)
        .onFirstAppear {
            viewModel.refresh()
        }
        .sinceLastDisappear { interval in
            refreshIfStale(sinceLastDisappear: interval)
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
                requestFromOffer()
            }

            Button(L10n.cancel, role: .cancel) {}
        } message: {
            Text(L10n.SeerrDetail.requestItTooMessage)
        }
        .errorMessage($actionError)
    }
}
