//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import Foundation
import SwiftUI

extension ItemActionButtons {

    /// Mark played / unplayed.
    ///
    /// On a group couch it reads "Mark watched for everyone", and marking unwatched
    /// first asks whether it is for everyone or just the primary user. The dialog is
    /// presented by `CouchLanguageLabel`, so it also works when this button sits in a menu.
    struct Played: View {

        @EnvironmentObject
        private var provider: ItemContentGroupProvider

        private var isPlayed: Bool {
            provider.item.userData?.isPlayed == true
        }

        private var title: String {
            if provider.isCouchGroup {
                isPlayed ? L10n.CouchItem.markUnwatchedForEveryone : L10n.CouchItem.markWatchedForEveryone
            } else {
                isPlayed ? L10n.markAsUnplayed : L10n.markAsPlayed
            }
        }

        var body: some View {
            Button(
                title,
                systemImage: ItemActionButton.played.systemImage
            ) {
                if !provider.isCouchGroup {
                    Task { await provider.toggleIsPlayed() }
                } else if isPlayed {
                    provider.isPresentingUnplayedChoice = true
                } else {
                    Task { await provider.setIsPlayedOnCouch(true, forEveryone: true) }
                }
            }
            .isSelected(isPlayed)
        }
    }
}

/// The toast after marking an item watched or unwatched on a group couch:
/// "Marked watched for Sam, Lisa and Tuur", or "Marked watched for Sam. Couldn't update Lisa".
///
/// Members who can't see the item (404) are skipped: they are neither named as
/// updated nor reported as a failure.
@MainActor
enum CouchPlayedFeedback {

    /// Long enough to read a sentence with names in it.
    private static var toastDuration: TimeInterval {
        #if os(tvOS)
        6
        #else
        5
        #endif
    }

    /// Mirrors the primary user's played state to every other member on the couch,
    /// waits for the result, and toasts who was updated.
    ///
    /// Call this after the primary user's own change succeeded.
    static func mirror(itemID: String, isPlayed: Bool, in userSession: UserSession) async {
        let result = await userSession.couchPlaybackService.mirrorPlayedResult(itemID: itemID, isPlayed: isPlayed)

        // Members without a stored sign-in have no member session, so the mirror never saw them.
        let reported = Set(result.synced + result.failed + result.notVisible)
        let withoutSignIn = userSession.couch
            .otherMembers
            .map(\.username)
            .filter { !reported.contains($0) }

        present(
            isPlayed: isPlayed,
            updated: [userSession.user.username] + result.synced,
            failed: result.failed + withoutSignIn,
            signInExpired: result.signInExpired + withoutSignIn
        )
    }

    /// Toasts that only the primary user was updated ("Just Tuur").
    static func presentPrimaryOnly(isPlayed: Bool, in userSession: UserSession) {
        present(isPlayed: isPlayed, updated: [userSession.user.username], failed: [], signInExpired: [])
    }

    /// Toasts that the primary user's own change failed, so nobody was updated.
    static func presentPrimaryFailure(in userSession: UserSession) {
        present(isPlayed: false, updated: [], failed: [userSession.user.username], signInExpired: [])
    }

    private static func present(isPlayed: Bool, updated: [String], failed: [String], signInExpired: [String]) {
        guard let message = message(
            isPlayed: isPlayed,
            updated: updated,
            failed: failed,
            signInExpired: signInExpired
        ) else { return }

        Container.shared
            .appToastProxy()
            .present(
                message,
                systemName: failed.isEmpty ? "checkmark.circle" : "exclamationmark.triangle",
                duration: toastDuration
            )
    }

    nonisolated static func message(
        isPlayed: Bool,
        updated: [String],
        failed: [String],
        signInExpired: [String]
    ) -> String? {
        let updatedSentence: String? = if updated.isEmpty {
            nil
        } else if isPlayed {
            L10n.CouchItem.markedWatched(ListFormatter.localizedString(byJoining: updated))
        } else {
            L10n.CouchItem.markedUnwatched(ListFormatter.localizedString(byJoining: updated))
        }

        let failedNames = ListFormatter.localizedString(byJoining: failed)
        let failedSentence: String? = if failed.isEmpty {
            nil
        } else if failed.allSatisfy({ signInExpired.contains($0) }) {
            L10n.CouchItem.couldNotUpdateSignIn(failedNames)
        } else {
            L10n.CouchItem.couldNotUpdate(failedNames)
        }

        switch (updatedSentence, failedSentence) {
        case let (first?, second?):
            return L10n.CouchItem.twoSentences(first, second)
        case let (first?, nil):
            return first
        case let (nil, second?):
            return second
        case (nil, nil):
            return nil
        }
    }
}
