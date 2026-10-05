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

extension ItemActionButtons {

    struct Playback: View {

        @EnvironmentObject
        private var provider: ItemContentGroupProvider

        @Default(.VideoPlayer.Playback.appMaximumBitrate)
        private var appMaximumBitrate

        @ViewContextContains(.isInMenu)
        private var isInMenu

        private var mediaSources: [MediaSourceInfo] {
            provider.mediaPlayerItemProvider?.item.mediaSources ?? []
        }

        private var supportedBitrates: [PlaybackBitrate] {
            provider.mediaPlayerItemProvider?.mediaSource?.supportedBitrates ?? []
        }

        @ViewBuilder
        private var versionPicker: some View {
            Picker(
                selection: Binding(
                    get: { provider.mediaPlayerItemProvider?.mediaSource },
                    set: { provider.select(.mediaSource($0)) }
                )
            ) {
                ForEach(mediaSources) { mediaSource in
                    Text(mediaSource.displayTitle)
                        .tag(mediaSource as MediaSourceInfo?)
                }
            } label: {
                Text(L10n.version)

                Text(provider.mediaPlayerItemProvider?.mediaSource?.displayTitle ?? L10n.none)
            }
            .pickerStyle(.menu)
        }

        @ViewBuilder
        private var qualityPicker: some View {
            Picker(
                selection: Binding(
                    get: { provider.mediaPlayerItemProvider?.requestedBitrate ?? appMaximumBitrate },
                    set: { provider.select(.bitrate($0)) }
                )
            ) {
                ForEach(supportedBitrates, id: \.rawValue) { bitrate in
                    Text(bitrate.displayTitle)
                        .tag(bitrate)
                }
            } label: {
                Text(L10n.playbackQuality)
                Text(provider.mediaPlayerItemProvider?.requestedBitrate.displayTitle)
            }
            .pickerStyle(.menu)
        }

        var body: some View {
            Menu(
                ItemActionButton.playback.displayTitle,
                systemImage: ItemActionButton.playback.systemImage
            ) {
                Section(L10n.source) {
                    if mediaSources.count > 1 {
                        versionPicker
                    }
                    qualityPicker
                }

                if CouchTrackPickers.hasTracks(for: provider) {
                    Section(L10n.tracks) {
                        CouchTrackPickers(provider: provider)
                    }
                }
            }
            .if(!isInMenu && UIDevice.isTV) { menu in
                menu.menuStyle(.button)
            }
        }
    }
}
