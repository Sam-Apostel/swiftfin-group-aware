//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import SwiftUI

/// A gentle note in the player when paused after the video stuttered a few times.
/// Not interactive: resuming playback dismisses it for the rest of the session.
struct PlaybackHealthStutterNote: View {

    @InjectedObject(\.playbackHealthMonitor)
    private var monitor: PlaybackHealthMonitor

    var body: some View {
        ZStack {
            if monitor.isPresentingStutterNote {
                Label {
                    Text(L10n.PlaybackHealth.stutterNote(count: monitor.stallCount, diagnosis: monitor.diagnosis))
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                } icon: {
                    Image(systemName: "waveform.path.ecg")
                }
                .font(UIDevice.isTV ? .callout : .subheadline)
                .padding(.horizontal, UIDevice.isTV ? 30 : 16)
                .padding(.vertical, UIDevice.isTV ? 20 : 12)
                .frame(maxWidth: UIDevice.isTV ? 900 : 480, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: UIDevice.isTV ? 24 : 14))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: monitor.isPresentingStutterNote)
        .allowsHitTesting(false)
    }
}
