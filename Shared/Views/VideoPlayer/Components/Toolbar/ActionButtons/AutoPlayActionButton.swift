//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import FactoryKit
import JellyfinAPI
import SwiftUI

// TODO: static width for tvOS

extension VideoPlayer.PlaybackControls.Toolbar.ActionButtons {

    struct AutoPlay: View {

        @ViewContextContains(.isInMenu)
        private var isInMenu

        /// Group couch only: this device's autoplay setting, `nil` follows the first person picked.
        @Default(.Couch.autoPlayNextEpisode)
        private var couchAutoPlayNextEpisode

        @EnvironmentObject
        private var manager: MediaPlayerManager

        @State
        private var userConfiguration: UserConfiguration

        @StateObject
        private var viewModel: ServerUserAdminViewModel

        @Toaster
        private var toaster

        /// The group couch, `nil` when watching alone.
        private var groupCouch: CouchGroup? {
            guard let couch = manager.userSession?.couch, couch.isGroup else { return nil }

            return couch
        }

        private var isAutoPlayEnabled: Bool {
            if let groupCouch {
                return couchAutoPlayNextEpisode ?? CouchAutoPlay.firstPickSetting(for: groupCouch)
            }

            return manager.userSession?.user.data.configuration?.enableNextEpisodeAutoPlay == true
        }

        private var systemImage: String {
            if isAutoPlayEnabled {
                VideoPlayerActionButton.autoPlay.systemImage
            } else {
                VideoPlayerActionButton.autoPlay.secondarySystemImage
            }
        }

        init() {
            let user = Container.shared.currentUserSession()?.user.data ?? UserDto()

            self.userConfiguration = user.configuration ?? UserConfiguration()
            self._viewModel = StateObject(wrappedValue: ServerUserAdminViewModel(user: user))
        }

        var body: some View {
            Button {
                let newValue = !isAutoPlayEnabled

                if groupCouch != nil {
                    // A group couch keeps autoplay on this device: kid-safe browsing can make a kid
                    // the session user, and nobody's server account should change.
                    couchAutoPlayNextEpisode = newValue
                } else {
                    userConfiguration.enableNextEpisodeAutoPlay = newValue
                    manager.userSession?.user.data.configuration = userConfiguration
                    viewModel.updateConfiguration(userConfiguration)
                }

                if newValue {
                    toaster.present("Auto Play on", systemName: "play.circle.fill")
                } else {
                    toaster.present("Auto Play off", systemName: "stop.circle")
                }
            } label: {
                Label(
                    L10n.autoPlay,
                    systemImage: systemImage
                )

                if isInMenu {
                    Text(isAutoPlayEnabled ? "On" : "Off")
                }
            }
            .if(isInMenu && !UIDevice.isTV) { button in
                button
                    .id(isAutoPlayEnabled)
            }
            .disabled(manager.queue == nil)
        }
    }
}
