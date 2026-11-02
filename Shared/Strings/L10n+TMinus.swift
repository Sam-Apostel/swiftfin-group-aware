//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

// MARK: - Report a problem and What's new (sent to and read from T-Minus)

extension L10n {

    enum ReportProblem {

        /// Settings row, screen title and send button context.
        static let title = "Report a problem"
        /// Video player: opens "Report a problem" about the item that's playing.
        static let fromPlayer = "Something wrong with this video?"

        /// Picker: what kind of report this is.
        static let kind = "What's up?"
        /// Report kind: a bug.
        static let broken = "Something's broken"
        /// Report kind: a feature request.
        static let idea = "Idea"

        /// Text field label: a short title for the report.
        static let summary = "In a few words"
        /// Prompt in the title field for a bug.
        static let brokenPrompt = "Subtitles drift out of sync"
        /// Prompt in the title field for an idea.
        static let ideaPrompt = "A sleep timer"
        /// Text field label: more details.
        static let details = "Details"
        /// Prompt in the details field.
        static let detailsPrompt = "What happened, and what did you expect?"

        /// Section header above the diagnostics that are attached to the report.
        static let sentAlong = "Sent along"
        /// Footer under the attached diagnostics.
        static let sentAlongFooter =
            "This helps track the problem down. No passwords, server addresses or watch history."

        /// Send button.
        static let send = "Send"

        /// Alert title after a report was sent.
        static let sentTitle = "Thanks, it's on its way"
        /// Alert message after a report was sent.
        static let sentMessage = "Every report gets read."
        /// Alert title when offline and the report was saved.
        static let savedTitle = "Saved for later"
        /// Alert message when offline and the report was saved.
        static let savedMessage = "You seem to be offline. Couchfin sends it the next time it opens."
        /// Alert title when sending failed.
        static let failedTitle = "Couldn't send that"
        /// Alert message when sending failed.
        static let failedMessage = "Something went wrong on the way. Try again in a bit."
    }

    enum WhatsNew {

        /// Settings row and screen title.
        static let title = "What's new"
        /// Title of the sheet shown once after an update.
        static let thisVersion = "What's new in this version"
        /// Section header: new things in this build.
        static let new = "New"
        /// Section header: things testers are asked to try.
        static let pleaseTry = "Please try"
        /// Empty state title when the build has no release notes.
        static let emptyTitle = "Nothing to share yet"
        /// Empty state description when the build has no release notes.
        static let emptyDescription = "Notes about new versions show up here."
        /// Button that closes the "What's new" sheet.
        static let gotIt = "Got it"

        /// Version and build, e.g. "Version 1.4.1 (202611021200)".
        static func version(_ version: String) -> String {
            "Version \(version)"
        }
    }
}
