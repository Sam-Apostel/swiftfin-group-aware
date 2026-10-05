//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

/// The availability of a Seerr title as shown in the detail screen's status pill.
///
/// Words: pending is "Waiting for approval", processing is "Requested", declined is "Declined"
/// (the same vocabulary as the rest of the Seerr screens).
enum SeerrMediaDetailStatus: Hashable {

    case available
    case blocklisted
    /// The latest request was declined and nothing else is in flight: it can be requested again.
    case declined
    case notRequested
    case partiallyAvailable
    /// Approved and on its way ("Requested").
    case processing
    /// Requested, waiting for an admin to approve it ("Waiting for approval").
    case requested

    var displayTitle: String {
        switch self {
        case .available:
            L10n.SeerrDetail.available
        case .blocklisted:
            L10n.SeerrDetail.blocklisted
        case .declined:
            L10n.SeerrDetail.declined
        case .notRequested:
            L10n.SeerrDetail.notRequested
        case .partiallyAvailable:
            L10n.SeerrDetail.partiallyAvailable
        case .processing:
            L10n.SeerrDetail.requested
        case .requested:
            L10n.SeerrDetail.waitingForApproval
        }
    }

    var systemImage: String {
        switch self {
        case .available:
            "checkmark.circle.fill"
        case .blocklisted:
            "nosign"
        case .declined:
            "xmark.circle.fill"
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
        case .blocklisted, .declined:
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

/// Whether the detail screen may offer Request for the current couch.
enum SeerrRequestGate: Hashable {

    /// A grown-up (or an unrestricted primary) can request it.
    case allowed
    /// Nobody on the couch may request (only restricted members): "Ask a grown-up" instead.
    case askAGrownUp
    /// A child is on the couch and the title is above kid level: no request at all.
    case notWithChild
}
