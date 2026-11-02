//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import AVFoundation
import MPVUI

// VLC applies `network-caching` when opening media, so it only gets steady playback on the next load.

extension AVMediaPlayerProxy: MediaPlayerBufferConfigurable {

    func setSteadyPlayback(_ isEnabled: Bool) {
        player.currentItem?.preferredForwardBufferDuration = isEnabled ? PlaybackHealthMemory.steadyForwardBufferSeconds : 0
    }
}

extension MPVMediaPlayerProxy: MediaPlayerBufferConfigurable {

    func setSteadyPlayback(_ isEnabled: Bool) {
        guard isEnabled else { return }

        for property in PlaybackHealthMemory.steadyMPVProperties {
            player.command("set", arguments: [property.name, property.value])
        }
    }
}
