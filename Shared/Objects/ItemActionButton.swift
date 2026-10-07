//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

enum ItemActionButton: String, CaseIterable, Displayable, Equatable, Identifiable, Storable, SystemImageable {

    case played
    case favorited
    case trailers
    case playback
    case record
    case subtitles
    case refresh
    case delete
    case audience
    #if os(iOS)
    case editMetadata
    #endif

    var displayTitle: String {
        switch self {
        case .played:
            L10n.played
        case .favorited:
            L10n.favorited
        case .trailers:
            L10n.trailers
        case .playback:
            L10n.playback
        case .record:
            L10n.record
        case .refresh:
            L10n.refreshMetadata
        case .subtitles:
            L10n.subtitles
        case .delete:
            L10n.delete
        case .audience:
            L10n.Audience.whosItFor
        #if os(iOS)
        case .editMetadata:
            L10n.edit
        #endif
        }
    }

    var id: String {
        rawValue
    }

    var systemImage: String {
        switch self {
        case .played:
            "checkmark"
        case .favorited:
            "heart.fill"
        case .trailers:
            "movieclapper"
        case .playback:
            "list.and.film"
        case .record:
            "record.circle.fill"
        case .refresh:
            "arrow.clockwise"
        case .subtitles:
            "captions.bubble"
        case .delete:
            "trash"
        case .audience:
            "bookmark.fill"
        #if os(iOS)
        case .editMetadata:
            "pencil"
        #endif
        }
    }

    var secondarySystemImage: String {
        switch self {
        case .favorited:
            "heart"
        case .record:
            "record.circle"
        case .audience:
            "bookmark"
        default:
            systemImage
        }
    }

    var activeColor: Color? {
        switch self {
        case .played:
            Color.Couchfin.glint
        case .favorited:
            .pink
        case .record:
            .red
        case .audience:
            Color.Couchfin.bloom
        default:
            nil
        }
    }

    #if os(tvOS)
    // tvOS shows 3 bar buttons + "…": keep the original trio, the audience goes after trailers
    static let defaultBarActionButtons: [ItemActionButton] = [
        .played,
        .favorited,
        .record,
        .trailers,
        .audience,
        .playback
    ]
    #else
    static let defaultBarActionButtons: [ItemActionButton] = [
        .played,
        .favorited,
        .audience,
        .record,
        .trailers,
        .playback
    ]
    #endif

    static let defaultMenuActionButtons: [ItemActionButton] = [
        .refresh,
        .subtitles,
        .delete
    ]
        #if os(iOS)
            .prepending(.editMetadata)
        #endif
}
