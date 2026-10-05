//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import FactoryKit
import Foundation

extension Notifications.Key {

    /// Posted when the progress of some couch members couldn't be saved at the
    /// end of playback.
    ///
    /// - Payload: Who, and why. Never includes members who can't see the item (404).
    static var couchSyncDidFail: Key<[CouchSyncFailure]> {
        Key("couchSyncDidFail")
    }
}

extension Container {

    /// The toast proxy of the app's root `OverlayToastView`, so services can toast
    /// above every screen.
    var appToastProxy: Factory<ToastProxy> {
        self { @MainActor in ToastProxy() }
            .singleton
    }

    var couchSyncFeedback: Factory<CouchSyncFeedback> {
        self { @MainActor in CouchSyncFeedback() }
            .singleton
    }
}

/// Toasts "Couldn't save progress for Lisa" when `couchSyncDidFail` is posted.
///
/// The toast waits until the player has closed, and holds during a run of
/// autoplayed episodes, so it never covers playback. Failures that arrive in the
/// meantime are combined into one toast. Success stays silent.
///
/// Created by `CouchPlaybackService`, so it listens before the first failure is posted.
@MainActor
final class CouchSyncFeedback {

    /// How often to check whether the player has closed.
    private static let pollInterval: Duration = .seconds(1)

    private var cancellables = Set<AnyCancellable>()
    private var pending: [CouchSyncFailure] = []
    private var presentTask: Task<Void, Never>?

    init() {
        Notifications[.couchSyncDidFail]
            .publisher
            .sink { [weak self] failures in
                Task { @MainActor in
                    self?.enqueue(failures)
                }
            }
            .store(in: &cancellables)
    }

    private func enqueue(_ failures: [CouchSyncFailure]) {
        for failure in failures {
            if let index = pending.firstIndex(where: { $0.name == failure.name }) {
                // A sign-in that ran out is the more useful reason to show.
                if failure.kind == .signInExpired {
                    pending[index] = failure
                }
            } else {
                pending.append(failure)
            }
        }

        guard presentTask == nil else { return }

        presentTask = Task { [weak self] in
            await self?.presentAfterPlayback()
        }
    }

    private func presentAfterPlayback() async {
        let userSessionManager = Container.shared.userSessionManager()

        // Always wait a moment, so the player's dismissal finishes first.
        repeat {
            try? await Task.sleep(for: Self.pollInterval)
        } while userSessionManager.hasActivePlayback

        let failures = pending
        pending = []
        presentTask = nil

        guard let message = Self.message(for: failures) else {
            return
        }

        Container.shared
            .appToastProxy()
            .present(message, systemName: "exclamationmark.triangle")
    }

    /// "Couldn't save progress for Lisa", plus who needs to sign in again.
    static func message(for failures: [CouchSyncFailure]) -> String? {
        guard failures.isNotEmpty else { return nil }

        let names = ListFormatter.localizedString(byJoining: failures.map(\.name))
        let expiredNames = failures
            .filter { $0.kind == .signInExpired }
            .map(\.name)

        if expiredNames.isEmpty {
            return L10n.CouchPlayback.couldNotSaveProgress(names)
        }

        if expiredNames.count == failures.count {
            return L10n.CouchPlayback.couldNotSaveProgressSignInExpired(names, count: expiredNames.count)
        }

        return L10n.CouchPlayback.couldNotSaveProgress(
            names,
            signInExpiredFor: ListFormatter.localizedString(byJoining: expiredNames),
            count: expiredNames.count
        )
    }
}
