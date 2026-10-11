//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

/// The availability of a Seerr title as shown in the detail screen's status pill.
enum SeerrMediaDetailStatus: Hashable {

    case available
    case blocklisted
    case notRequested
    case partiallyAvailable
    case processing
    case requested

    var displayTitle: String {
        switch self {
        case .available:
            L10n.SeerrDetail.available
        case .blocklisted:
            L10n.SeerrDetail.blocklisted
        case .notRequested:
            L10n.SeerrDetail.notRequested
        case .partiallyAvailable:
            L10n.SeerrDetail.partiallyAvailable
        case .processing:
            L10n.SeerrDetail.processing
        case .requested:
            L10n.SeerrDetail.requested
        }
    }

    var systemImage: String {
        switch self {
        case .available:
            "checkmark.circle.fill"
        case .blocklisted:
            "nosign"
        case .notRequested:
            "circle.dashed"
        case .partiallyAvailable:
            "circle.lefthalf.filled"
        case .processing:
            "arrow.down.circle.fill"
        case .requested:
            "clock.fill"
        }
    }

    var color: Color {
        switch self {
        case .available, .partiallyAvailable:
            .green
        case .blocklisted:
            .red
        case .notRequested:
            .secondary
        case .processing:
            .blue
        case .requested:
            .orange
        }
    }
}
