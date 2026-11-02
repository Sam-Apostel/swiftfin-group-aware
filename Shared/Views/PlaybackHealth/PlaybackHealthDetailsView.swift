//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

/// Explains the pre-play verdict in plain words, with the copy that would fix it behind a disclosure.
struct PlaybackHealthDetailsView: View {

    @State
    private var isShowingFix = false

    let verdict: PlaybackHealthVerdict
    let onClose: () -> Void

    private var reasons: [PlaybackHealthReason] {
        verdict.reasons
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.PlaybackHealth.tierTitle(verdict.tier))
                            .font(.headline)

                        Text(L10n.PlaybackHealth.tierDescription(verdict.tier))
                            .foregroundStyle(.secondary)
                    }

                    if reasons.isNotEmpty || verdict.stalledBefore > 0 {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.PlaybackHealth.whyTitle)
                                .font(.headline)

                            if verdict.stalledBefore > 0 {
                                Label(L10n.PlaybackHealth.stalledBefore(verdict.stalledBefore), systemImage: "pause.circle")
                            }

                            ForEach(reasons, id: \.self) { reason in
                                Label(L10n.PlaybackHealth.reason(reason), systemImage: "circle.fill")
                                    .labelStyle(PlaybackHealthBulletLabelStyle())
                            }
                        }
                    }

                    if let target = verdict.target {
                        #if os(tvOS)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.PlaybackHealth.fixTitle)
                                .font(.headline)

                            Text(L10n.PlaybackHealth.targetDescription(target))
                                .foregroundStyle(.secondary)
                        }
                        #else
                        DisclosureGroup(L10n.PlaybackHealth.fixTitle, isExpanded: $isShowingFix) {
                            Text(L10n.PlaybackHealth.targetDescription(target))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 6)
                        }
                        #endif
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .edgePadding()
            }
            .navigationTitle(L10n.PlaybackHealth.title)
            .toolbarTitleDisplayMode(.inline)
            #if os(iOS)
            .navigationBarCloseButton {
                onClose()
            }
            #endif
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
    }
}

/// A small bullet in front of each reason.
private struct PlaybackHealthBulletLabelStyle: LabelStyle {

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon
                .font(.system(size: 6))
                .foregroundStyle(.secondary)

            configuration.title
        }
    }
}
