//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension Notifications.Key {

    /// A "Who's it for?" save or removal failed, and the screen that started it can't show an alert.
    /// For example, a poster context menu is gone by the time its save finishes.
    ///
    /// - Payload: The localized error description.
    static var audienceWatchlistSaveDidFail: Key<String> {
        Key("audienceWatchlistSaveDidFail")
    }
}

extension View {

    /// Shows an error alert for every `audienceWatchlistSaveDidFail` notification.
    /// Attach it once, to a view that stays on screen (the main tab view).
    func audienceWatchlistSaveErrorAlert() -> some View {
        modifier(AudienceWatchlistSaveErrorAlertModifier())
    }
}

private struct AudienceWatchlistSaveErrorAlertModifier: ViewModifier {

    @State
    private var error: Error?

    func body(content: Content) -> some View {
        content
            .onNotification(.audienceWatchlistSaveDidFail) { message in
                // The picker dismisses itself right after starting the save, and a fast failure
                // (offline, no account) arrives while its sheet is still animating out.
                // An alert presented during that dismissal is dropped, so wait for it to finish.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(800))
                    error = ErrorMessage(message)
                }
            }
            .errorMessage($error)
    }
}
