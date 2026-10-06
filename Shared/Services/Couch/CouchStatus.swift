//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Defaults
import FactoryKit
import Foundation
import Logging

/// What the couch looks like right now, said the same way on Home and in Settings:
/// who it browses as, whether watched titles are hidden, and whose account couldn't be checked.
enum CouchStatus {

    /// A couch member whose last request failed (`CouchMemberHealth`).
    struct MemberIssue: Equatable, Identifiable {

        let member: UserState
        let kind: CouchMemberHealth.Kind

        var id: String {
            member.id
        }

        /// Signing in again fixes it: the server refused the member's sign-in, or none is stored.
        var canSignInAgain: Bool {
            kind == .unauthorized
        }

        /// "Lisa needs to sign in again" / "Couldn't check Lisa — their history isn't counted"
        var message: String {
            switch kind {
            case .unauthorized:
                L10n.CouchHomeStatus.needsSignIn(member.username)
            case .transient:
                L10n.CouchHomeStatus.couldNotCheck(member.username)
            }
        }

        var systemImage: String {
            switch kind {
            case .unauthorized:
                "person.crop.circle.badge.exclamationmark"
            case .transient:
                "exclamationmark.triangle.fill"
            }
        }
    }

    // MARK: - Browsing as

    /// "Browsing as Tuur (kid-safe)" when kid-safe browsing made a restricted member the primary user
    /// instead of the first person picked. `nil` otherwise, also on a solo couch.
    ///
    /// - Parameter lastMemberIDs: The couch's pick order, `Defaults[.Couch.lastMemberIDs]`.
    static func browsingAsDescription(couch: CouchGroup, lastMemberIDs: [String]) -> String? {
        guard couch.isGroup, couch.primary.isRestricted else { return nil }

        let firstPickID = lastMemberIDs.first { couch.memberIDs.contains($0) }

        if let firstPickID, firstPickID == couch.primary.id {
            return nil
        }

        return L10n.CouchSettings.browsingAsKidSafe(couch.primary.username)
    }

    /// The couch's one-line status: `browsingAsDescription(couch:lastMemberIDs:)` when there is one,
    /// otherwise "On the couch: Sam, Lisa and Tuur".
    static func headline(couch: CouchGroup, lastMemberIDs: [String]) -> String {
        browsingAsDescription(couch: couch, lastMemberIDs: lastMemberIDs)
            ?? L10n.CouchSettings.onTheCouch(couch.displayNames)
    }

    // MARK: - Hiding watched

    /// Whether the couch rows and the decider hide what anyone on the couch watched.
    /// Only a group couch hides anything for that setting.
    ///
    /// - Parameter hideWatchedByAnyMember: `Defaults[.Couch.hideWatchedByAnyMember]`.
    static func isHidingWatched(couch: CouchGroup, hideWatchedByAnyMember: Bool) -> Bool {
        couch.isGroup && hideWatchedByAnyMember
    }

    // MARK: - Member health

    /// The members on this couch whose last request failed, in couch order.
    ///
    /// - Parameter failures: `CouchMemberHealth.failures`, by Jellyfin user id.
    static func memberIssues(
        couch: CouchGroup,
        failures: [String: CouchMemberHealth.Kind]
    ) -> [MemberIssue] {
        couch.members.compactMap { member in
            guard let kind = failures[member.id] else { return nil }

            return MemberIssue(member: member, kind: kind)
        }
    }
}

// MARK: - Sign in again

/// Rebuilds the couch after a member signed in again from Home.
///
/// Member sessions read their access token once (`UserSession.memberSessions`), so after someone
/// signs in again the couch keeps using the dead token until it is signed in again itself.
/// `UserSignInView` only posts `Notifications[.didAddUser]` and never signs in, so this listens for it:
/// for a member whose sign-in was opened from Home (`willSignInAgain(userID:)`), it signs the current
/// couch in again in pick order (`UserSessionManager.pickOrderedMemberIDs(of:)`), never during playback.
@MainActor
final class CouchSignInAgain {

    static let shared = CouchSignInAgain()

    /// How long a "Sign in again" from Home waits for that person to finish signing in.
    private static let pendingLifetime: TimeInterval = 15 * 60

    /// How often a re-sign-in held back by playback checks again.
    private static let playbackPollInterval: Duration = .seconds(5)

    /// The members whose sign-in was opened from Home, with when.
    private var pending: [String: Date] = [:]

    private var rebuildTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    private let logger = Logger.swiftfin()

    private init() {
        Notifications[.didAddUser]
            .publisher
            .sink { [weak self] user in
                self?.didAddUser(user)
            }
            .store(in: &cancellables)
    }

    /// Call right before routing to `.userSignIn(server:username:)` for a couch member.
    func willSignInAgain(userID: String) {
        pending[userID] = .now
    }

    private func didAddUser(_ user: UserState) {
        let now = Date.now
        pending = pending.filter { now.timeIntervalSince($0.value) < Self.pendingLifetime }

        guard pending.removeValue(forKey: user.id) != nil else { return }

        let userSessionManager = Container.shared.userSessionManager()

        guard let couch = userSessionManager.currentSession?.couch,
              couch.memberIDs.contains(user.id)
        else { return }

        rebuildTask?.cancel()
        rebuildTask = Task { [weak self] in
            await self?.signInCouchAgain(couchID: couch.id)
        }
    }

    /// Signs the current couch in again in pick order, once nothing is playing.
    ///
    /// Gives up when the couch changed meanwhile (someone else already rebuilt it).
    private func signInCouchAgain(couchID: String) async {
        let userSessionManager = Container.shared.userSessionManager()

        // Let the sign-in sheet finish closing before the session changes
        do {
            try await Task.sleep(for: .milliseconds(600))

            while userSessionManager.hasActivePlayback {
                try await Task.sleep(for: Self.playbackPollInterval)
            }
        } catch {
            return
        }

        guard let couch = userSessionManager.currentSession?.couch, couch.id == couchID else { return }

        do {
            try await userSessionManager.signIn(userIDs: userSessionManager.pickOrderedMemberIDs(of: couch))
        } catch {
            logger.error(
                "Couch: unable to sign the couch in again after a member signed in",
                metadata: ["error": .string(error.localizedDescription)]
            )
        }
    }
}
