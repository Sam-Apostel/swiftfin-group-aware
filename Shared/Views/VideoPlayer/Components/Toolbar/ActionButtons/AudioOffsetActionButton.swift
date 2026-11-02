//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension VideoPlayer.PlaybackControls.Toolbar.ActionButtons {

    struct AudioOffset: View {

        @ViewContextContains(.isInMenu)
        private var isInMenu

        @Environment(ViewState.self)
        private var viewState
        @EnvironmentObject
        private var manager: MediaPlayerManager

        var body: some View {
            Button {
                // Opening the studio pauses playback and remembers where
                let model = SyncStudioModel(manager: manager, viewState: viewState)
                viewState.presentGuestSupplement(SyncStudioSupplement(model: model))
            } label: {
                Label(
                    L10n.AVSync.fixAudioSync,
                    systemImage: VideoPlayerActionButton.audioOffset.systemImage
                )

                if isInMenu, manager.audioOffset != .zero {
                    Text(manager.audioOffset, format: .playbackOffset)
                }
            }
        }
    }
}
