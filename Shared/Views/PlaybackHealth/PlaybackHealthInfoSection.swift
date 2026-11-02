//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import SwiftUI

/// The live stutter diagnosis, shown in the player's playback information.
struct PlaybackHealthInfoSection: View {

    @InjectedObject(\.playbackHealthMonitor)
    private var monitor: PlaybackHealthMonitor

    var body: some View {
        Text(L10n.PlaybackHealth.health)
            .font(.subheadline)
            .fontWeight(.semibold)
            .padding(.vertical, 4)

        LabeledContent(L10n.PlaybackHealth.stalls, value: monitor.stallCount.description)

        if let diagnosis = monitor.diagnosis {
            LabeledContent(L10n.PlaybackHealth.diagnosis, value: L10n.PlaybackHealth.diagnosisTitle(diagnosis))
        }

        if let framerate = monitor.latestSample?.framerate, monitor.latestSample?.isVideoDirect != true {
            LabeledContent(
                L10n.PlaybackHealth.serverSpeed,
                value: L10n.PlaybackHealth.framerate(framerate, needed: monitor.sourceFramerate)
            )
        }

        LabeledContent(
            L10n.PlaybackHealth.steadyPlayback,
            value: monitor.isSteadyPlayback ? L10n.PlaybackHealth.on : L10n.PlaybackHealth.off
        )
    }
}
