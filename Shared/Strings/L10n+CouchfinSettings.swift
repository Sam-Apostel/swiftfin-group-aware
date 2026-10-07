//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

// MARK: - Settings, regrouped for Couchfin

extension L10n {

    enum CouchfinSettings {

        /// Settings root group: what happens while you watch.
        static let watching = "Watching"
        /// Settings root group: how the app looks.
        static let look = "Look"
        /// Settings root group: account, server and requests.
        static let connections = "Connections"

        /// Settings screen: player, quality, autoplay, skip lengths and player controls.
        static let playback = "Playback"
        /// Settings screen: audio and subtitle languages, modes and the subtitle look.
        static let audioAndSubtitles = "Audio & subtitles"
        /// Settings row: kid-safe browsing, hiding watched titles and who's a kid.
        static let couchAndKids = "Couch & kids"
        /// Settings screen: home rows, library layout and filters, the tvOS tab bar.
        static let homeAndLibraries = "Home & libraries"
        /// Settings screen: poster labels and indicators, and the item page.
        static let postersAndItems = "Posters & item pages"
        /// Settings row value next to the signed-in person: their account, password and app lock.
        static let accountAndLock = "Account & lock"
        /// Settings row: the Jellyfin server's admin dashboard.
        static let serverDashboard = "Server dashboard"
        /// Settings row and screen: version, app-wide options and diagnostics.
        static let about = "About Couchfin"

        /// Playback section: autoplay, skip lengths, resume offset, remaining time.
        static let whileWatching = "While watching"
        /// Playback section: player buttons, gestures, supplements and the scrubber.
        static let controls = "Controls"

        /// About section: settings that apply to the whole app, before anyone signs in.
        static let app = "App"
        /// About section: logs, experimental features and debug tools.
        static let diagnostics = "Diagnostics"
        /// Couch & kids section on Apple TV: settings for the current Apple TV profile.
        static let appleTVProfile = "This Apple TV profile"
        /// Couch & kids row: the person Couchfin opens as for this Apple TV profile.
        static let opensAs = "Opens as"
        /// "Opens as" value: no default person, show the couch picker.
        static let askEveryTime = "Ask every time"
        /// Footer under "Opens as".
        static let opensAsFooter =
            "When someone switches to this Apple TV profile, Couchfin opens with just this person on the couch. Changing the couch in the app sticks until the profile changes."

        /// About footer under the source code and license links.
        static let builtOnSwiftfin = "Couchfin is built on Swiftfin, the open-source Jellyfin client."
    }
}
