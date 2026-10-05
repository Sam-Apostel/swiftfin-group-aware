//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

extension NavigationRoute {

    // MARK: - Audience Picker

    /// "Who's it for?" for anything (e.g. a Seerr title). The caller saves in `onSave` / `onRemove`.
    /// A sheet on iOS, a full-screen cover on tvOS.
    @MainActor
    static func audiencePicker(
        title: String,
        initialAudience: Set<String>,
        isExisting: Bool,
        onSave: @escaping (Set<String>) -> Void,
        onRemove: (() -> Void)? = nil
    ) -> NavigationRoute {
        NavigationRoute(
            id: "audiencePicker",
            style: .sheet
        ) {
            AudiencePickerView(
                title: title,
                initialAudience: initialAudience,
                isExisting: isExisting,
                onSave: onSave,
                onRemove: onRemove
            )
        }
    }

    /// "Who's it for?" for a Jellyfin library item (movie or series): pre-filled with the
    /// existing entry or the current couch, saves to the audience watchlist store itself.
    @MainActor
    static func audiencePicker(
        item: BaseItemDto,
        completion: ((Result<AudienceWatchlistActions.Outcome, Error>) -> Void)? = nil
    ) -> NavigationRoute {
        NavigationRoute(
            id: "audiencePicker-\(item.id ?? "unknown")",
            style: .sheet
        ) {
            ItemAudiencePickerView(
                item: item,
                completion: completion
            )
        }
    }
}
