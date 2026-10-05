//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import Foundation
import Logging

extension ReadyAlertsService {

    /// How many requests are read with the API key (it sees everyone's).
    static let apiKeyRequestCount = 100

    /// How many requests are read per signed-in person without an API key.
    static let personalRequestCount = 50

    /// The household's recent Seerr requests, merged by request id, newest first.
    ///
    /// `SeerrService` is bound to the current session's server, so Seerr is only used when `session` is on that server.
    /// A cold background launch has no current session and degrades to watchlist only.
    /// Never throws: every failing call is logged and skipped.
    func seerrRequests(session: UserSession, householdUserIDs: Set<String>) async -> [SeerrRequest] {
        guard Container.shared.currentUserSession()?.server.id == session.server.id else { return [] }

        let seerrService = Container.shared.seerrService()

        guard let client = seerrService.client else { return [] }

        var requestsByID: [Int: SeerrRequest] = [:]

        if seerrService.hasAPIKey {
            do {
                for request in try await client.requests(take: Self.apiKeyRequestCount) {
                    requestsByID[request.id] = request
                }
            } catch {
                logger.error("Ready alerts: reading Seerr requests failed: \(error.localizedDescription)")
            }
        } else {
            let userIDs = seerrService.signedInUserIDs.intersection(householdUserIDs).sorted()

            for userID in userIDs {
                do {
                    let requests = try await seerrService.perform(asJellyfinUserID: userID) { userClient in
                        try await userClient.requests(take: Self.personalRequestCount)
                    }

                    for request in requests {
                        requestsByID[request.id] = request
                    }
                } catch {
                    logger.error("Ready alerts: reading Seerr requests of user \(userID) failed: \(error.localizedDescription)")
                }
            }
        }

        return requestsByID.values.sorted { $0.id > $1.id }
    }
}
