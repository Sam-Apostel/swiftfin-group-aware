//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {

    /// Called when downloads finished while the app wasn't running.
    /// Creating the download manager reconnects to the background session,
    /// which then delivers the events and calls the handler.
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == DownloadManager.sessionIdentifier else {
            completionHandler()
            return
        }

        MainActor.assumeIsolated {
            Container.shared.downloadManager().backgroundCompletionHandler = completionHandler
        }
    }
}
