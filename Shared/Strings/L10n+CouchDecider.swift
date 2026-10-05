//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

// MARK: - "What should we watch?" decider

// Reused existing keys: L10n.any, L10n.all, L10n.movies, L10n.details, L10n.play, L10n.close, L10n.retry.

extension L10n {

    enum CouchDecider {

        // MARK: Home entry

        static let whatShouldWeWatch = "What should we watch?"

        /// - Parameter names: A localized list of names, e.g. `CouchGroup.displayNames`.
        static func letCouchfinPick(_ names: String) -> String {
            "Let Couchfin pick for \(names)"
        }

        // MARK: Header

        /// - Parameter names: A localized list of names, e.g. `CouchGroup.displayNames`.
        static func tonightFor(_ names: String) -> String {
            "Tonight for \(names)"
        }

        /// The header on a solo couch.
        static let tonightForYou = "Tonight for you"

        /// - Parameter names: A localized list of the restricted members' names.
        static func kidSafeFor(_ names: String) -> String {
            "Kid-safe for \(names)"
        }

        /// Kids without a parental rating on the server: only rated titles, checked in the app.
        ///
        /// - Parameter names: A localized list of the kids' names.
        static func kidSafeLocalOnly(_ names: String) -> String {
            "Kid-safe for \(names) (rated titles only · set a parental rating in Jellyfin)"
        }

        /// - Parameter names: A localized list of the restricted members' names.
        static func onlyPicksFor(_ names: String) -> String {
            "Only titles picked for this couch — couldn't check \(names)'s account"
        }

        /// The iPhone header button that opens "Let everyone vote".
        static let vote = "Vote"

        // MARK: Actions

        static let notTonight = "Not tonight"
        static let shuffle = "Shuffle"
        static let watch = "Watch"

        // MARK: Filters

        static let lessThanOneHour = "< 1h"
        static let lessThanOneHour45 = "< 1h45"
        static let lessThanTwoHours30 = "< 2h30"
        static let shows = "Shows"
        static let clear = "Clear"

        /// VoiceOver labels of the length chips (the chips show "< 1h", "< 1h45", "< 2h30").
        static let underOneHour = "Under 1 hour"
        static let underOneHour45 = "Under 1 hour 45 minutes"
        static let underTwoHours30 = "Under 2 hours 30 minutes"

        /// Brings back the title just hidden with "Not tonight".
        static let undo = "Undo"
        static let undoNotTonight = "Undo Not tonight"

        /// The titles hidden with "Not tonight". Pressing the chip brings them all back.
        static func hiddenCount(_ count: Int) -> String {
            "Hidden: \(count)"
        }

        // MARK: Card

        /// Short season label on the card, e.g. "S2".
        static func seasonShort(_ number: Int) -> String {
            "S\(number)"
        }

        /// Short episode label on the card, e.g. "E5".
        static func episodeShort(_ number: Int) -> String {
            "E\(number)"
        }

        /// Solo couch. Also the title of Home's solo "Picked for you" row.
        static let pickedForYou = "Picked for you"
        static let pickedForThisCouch = "Picked for this couch"
        static let nextUpTogether = "Next up together"
        static let nextUpSolo = "Next up"
        static let newForAllOfYou = "New for all of you"
        static let newForYou = "New for you"
        static let fromYourLibrary = "From your library"

        // MARK: States

        static let lookingAtWhatYouHave = "Looking at what you all have…"
        static let nothingToSuggest = "Nothing to suggest yet"
        static let nothingToSuggestHint = "Tag titles for this couch with *Who's it for?*"
        static let nothingMatches = "Nothing matches"
        static let clearFilters = "Clear filters"
        static let startingOver = "You've seen them all, starting over"
        static let browse = "Browse"

        /// The empty pool when a restricted member's account couldn't be checked.
        ///
        /// - Parameter names: A localized list of the restricted members' names.
        static func couldNotCheckAccount(_ names: String) -> String {
            "Couldn't check \(names)'s account"
        }

        static let couldNotCheckAccountHint = "Until then, only titles picked for this couch can be suggested."

        /// The empty pool when the rating ceiling for kids without a parental rating left nothing.
        ///
        /// - Parameter names: A localized list of the kids' names.
        static func nothingRatedFor(_ names: String) -> String {
            "Only titles rated PG or lower are suggested for \(names). Set a parental rating in Jellyfin, or tag titles with *Who's it for?*"
        }

        /// Restores the titles hidden with "Not tonight".
        static func bringBack(_ count: Int) -> String {
            "Bring back \(count)"
        }
    }
}
