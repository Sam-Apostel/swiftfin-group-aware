//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Foundation

extension Defaults.Keys {

    enum PlaybackHealth {

        /// Buffer further ahead for items that stalled before on this device.
        static let steadyPlayback: Key<Bool> = Key("playbackHealthSteadyPlayback", default: true, suite: .appSuite)

        /// Rebuffering stalls per item ID on this device, from the worst session.
        static let stalledItems: Key<[String: Int]> = Key("playbackHealthStalledItems", default: [:], suite: .appSuite)
    }
}

/// What this device remembers about items that stuttered, and the "steady playback" buffer sizes.
enum PlaybackHealthMemory {

    /// The most items remembered. The oldest knowledge isn't tracked, so a random excess is dropped.
    static let maxRememberedItems = 500

    /// AVPlayer forward buffer in steady playback.
    static let steadyForwardBufferSeconds: Double = 60
    /// VLC `network-caching` in steady playback (default is about 1 second).
    static let steadyVLCNetworkCachingMilliseconds = 10000
    /// mpv properties in steady playback: a bigger demuxer cache reads further ahead.
    static let steadyMPVProperties: [(name: String, value: String)] = [
        ("cache", "yes"),
        ("demuxer-max-bytes", "400MiB"),
    ]

    static func stalls(for itemID: String?) -> Int {
        guard let itemID else { return 0 }

        return Defaults[.PlaybackHealth.stalledItems][itemID] ?? 0
    }

    /// Whether the player should buffer further ahead for this item.
    static func isSteadyPlayback(for itemID: String?) -> Bool {
        Defaults[.PlaybackHealth.steadyPlayback] && stalls(for: itemID) > 0
    }

    static func recordStalls(_ count: Int, for itemID: String?) {
        guard let itemID, count > 0 else { return }

        var items = Defaults[.PlaybackHealth.stalledItems]
        items[itemID] = max(items[itemID] ?? 0, count)

        while items.count > maxRememberedItems, let key = items.keys.first(where: { $0 != itemID }) {
            items.removeValue(forKey: key)
        }

        Defaults[.PlaybackHealth.stalledItems] = items
    }
}
