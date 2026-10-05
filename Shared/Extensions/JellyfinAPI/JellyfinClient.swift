//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import Get
import JellyfinAPI
import UIKit

extension JellyfinClient.Configuration {

    /// - Parameter deviceIDSuffix: When set, it is appended to the device ID so that
    ///   the client gets its own server session. Used by couch member sessions, so their
    ///   calls never take over the primary user's server session on this device.
    static func swiftfinConfiguration(
        url: URL,
        accessToken: String? = nil,
        deviceIDSuffix: String? = nil
    ) -> Self {

        let client = "Swiftfin \(UIDevice.platform)"
        let deviceName = UIDevice.current
            .name
            .folding(options: .diacriticInsensitive, locale: .current)
            .unicodeScalars
            .filter { CharacterSet.urlQueryAllowed.contains($0) }
            .description
        var deviceID = "\(UIDevice.platform)_\(UIDevice.vendorUUIDString)"

        if let deviceIDSuffix {
            deviceID += "_\(deviceIDSuffix)"
        }

        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.1"

        return .init(
            url: url,
            accessToken: accessToken,
            client: client,
            deviceName: deviceName,
            deviceID: deviceID,
            version: version
        )
    }
}
