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
import Get
import Logging

extension Container {

    var couchMemberHealth: Factory<CouchMemberHealth> {
        self { @MainActor in CouchMemberHealth() }
            .singleton
    }
}

/// Which couch members couldn't be checked by the couch rows, and why.
///
/// `CouchHomeSupport.perSession` (every per-member request of the couch rows and the decider)
/// records a member's failure here and clears it on the member's next success.
/// Home shows it, so nobody wonders why a row is short: "Tuur needs to sign in again".
@MainActor
final class CouchMemberHealth: ObservableObject {

    enum Kind: Equatable {

        /// The server refused the member's sign-in (401/403), or no sign-in is stored:
        /// signing in again fixes it.
        case unauthorized

        /// Anything else (network, server error). The next refresh may succeed.
        case transient
    }

    /// The members whose last request failed, by Jellyfin user id.
    @Published
    private(set) var failures: [String: Kind] = [:]

    /// A home refresh fans out to several rows within moments. A failure that was logged
    /// less than this long ago (with the same kind) isn't logged again.
    private static let logInterval: TimeInterval = 30

    private var lastLogged: [String: (kind: Kind, date: Date)] = [:]

    private let logger = Logger.swiftfin()

    init() {}

    // MARK: - Queries

    /// The failures of the members on this couch.
    func failures(for couch: CouchGroup) -> [String: Kind] {
        let memberIDs = couch.memberIDs
        return failures.filter { memberIDs.contains($0.key) }
    }

    /// The members on this couch whose sign-in has to be renewed, in couch order.
    func membersNeedingSignIn(on couch: CouchGroup) -> [UserState] {
        couch.members.filter { failures[$0.id] == .unauthorized }
    }

    // MARK: - Recording

    /// Records a failed request for a member. Cancelled requests (a refresh that was replaced) are ignored.
    func recordFailure(userID: String, error: Error) {
        guard let kind = Self.kind(of: error) else { return }

        recordFailure(userID: userID, kind: kind, reason: error.localizedDescription)
    }

    /// Records a failure for a member, logged at most once per member per refresh.
    func recordFailure(userID: String, kind: Kind, reason: String) {
        if failures[userID] != kind {
            failures[userID] = kind
        }

        if let last = lastLogged[userID],
           last.kind == kind,
           Date.now.timeIntervalSince(last.date) < Self.logInterval
        {
            return
        }

        lastLogged[userID] = (kind: kind, date: .now)

        logger.warning(
            "Couch: could not check a member",
            metadata: [
                "memberID": .stringConvertible(userID),
                "kind": .stringConvertible(kind == .unauthorized ? "unauthorized" : "transient"),
                "reason": .stringConvertible(reason),
            ]
        )
    }

    /// Clears a member after a successful request.
    func recordSuccess(userID: String) {
        lastLogged[userID] = nil

        if failures[userID] != nil {
            failures[userID] = nil
        }
    }

    /// Forgets every failure, e.g. when the couch changes.
    func reset() {
        lastLogged = [:]

        if failures.isNotEmpty {
            failures = [:]
        }
    }

    // MARK: - Classification

    /// The kind of a failed request, or `nil` for a cancelled one.
    nonisolated static func kind(of error: Error) -> Kind? {
        if error is CancellationError {
            return nil
        }

        if let urlError = error as? URLError, urlError.code == .cancelled {
            return nil
        }

        if case let .unacceptableStatusCode(statusCode)? = error as? Get.APIError,
           statusCode == 401 || statusCode == 403
        {
            return .unauthorized
        }

        return .transient
    }
}
