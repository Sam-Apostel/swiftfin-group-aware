//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

// "Report a problem" and "What's new", backed by T-Minus.

extension NavigationRoute {

    static var reportProblem: NavigationRoute {
        NavigationRoute(
            id: "report-problem"
        ) {
            ReportProblemView()
        }
    }

    /// From the video player: a sheet that also describes what's playing.
    @MainActor
    static func reportPlaybackProblem(_ playback: PlaybackReportContext) -> NavigationRoute {
        NavigationRoute(
            id: "report-playback-problem",
            style: .sheet
        ) {
            ReportProblemView(playback: playback, isPresentedAsSheet: true)
        }
    }

    static var whatsNew: NavigationRoute {
        NavigationRoute(
            id: "whats-new"
        ) {
            WhatsNewView()
        }
    }
}
