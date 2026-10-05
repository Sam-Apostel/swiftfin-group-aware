//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

extension SeerrMediaDetailView {

    /// Scrolling content under a transparent navigation bar, like `ItemView`'s
    /// compact enhanced layout (`ItemView.BlurredNavigationBarScrollView`).
    struct ContentView: View {

        @ObservedObject
        var viewModel: SeerrMediaDetailViewModel

        let details: SeerrMediaDetails
        let onPlay: (BaseItemDto) -> Void
        let onRequest: () -> Void
        let onWhoIsItFor: () -> Void

        var body: some View {
            WithBlurNavigationBar {
                ScrollContent(
                    viewModel: viewModel,
                    details: details,
                    onPlay: onPlay,
                    onRequest: onRequest,
                    onWhoIsItFor: onWhoIsItFor
                )
            }
            .ignoresSafeArea()
            .trackingFrame(for: .scrollView)
        }
    }

    private struct ScrollContent: View {

        @Environment(\.frameForParentView)
        private var frameForParentView

        @ObservedObject
        var viewModel: SeerrMediaDetailViewModel

        let details: SeerrMediaDetails
        let onPlay: (BaseItemDto) -> Void
        let onRequest: () -> Void
        let onWhoIsItFor: () -> Void

        @ViewBuilder
        private var topBlur: some View {
            Rectangle()
                .fill(Material.ultraThin)
                .mask(gradient: .eased(.smootherstep)) {
                    (location: 0, opacity: 1)
                    (location: 1, opacity: 0)
                }
                .frame(
                    height: frameForParentView[.scrollView, default: .zero]
                        .safeAreaInsets.top + 20
                )
                .offset(
                    y: -frameForParentView[.scrollView, default: .zero]
                        .safeAreaInsets.top
                )
                .colorScheme(.dark)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Header(
                        viewModel: viewModel,
                        details: details,
                        onPlay: onPlay,
                        onRequest: onRequest,
                        onWhoIsItFor: onWhoIsItFor
                    )

                    if details.cast.isNotEmpty {
                        CastSection(cast: details.cast)
                    }
                }
                .edgePadding(.bottom)
            }
            .ignoresSafeArea(edges: .horizontal)
            .scrollIndicators(.hidden)
            .backport
            .scrollEdgeEffectStyle(.soft, for: .top)
            .overlay(alignment: .top) {
                topBlur
            }
        }
    }
}
