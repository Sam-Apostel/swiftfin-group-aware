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
import Logging

/// The setup state machine of the tvOS Discover tab, over `SeerrService`'s published state.
///
/// 1. `checking`: adopting the household's Seerr server (`adoptHouseholdServerIfNeeded()`).
/// 2. `needsServer`: no server here and none (reachable) in the household.
/// 3. `needsSignIn`: a server is known, but nobody on this Apple TV has a Seerr session yet.
///    Right after adopting the household's server the couch is signed in without a press
///    (`signingIn`), unless someone explicitly signed out in the Seerr settings.
/// 4. `ready`: `SeerrService.client` is set.
@MainActor
final class SeerrTVSetupViewModel: ObservableObject {

    enum Phase: Equatable {
        case checking
        case needsServer
        case needsSignIn
        /// Signing in the couch with Quick Connect; the name of the person being signed in.
        case signingIn(String)
        case ready
    }

    /// The first failure of a couch sign-in, shown inline on the sign-in screen.
    struct SignInFailure: Equatable {
        /// Who couldn't be signed in.
        let name: String
        let message: String
    }

    @Published
    private(set) var phase: Phase
    /// The household server adoption tried, when it failed.
    @Published
    private(set) var attemptedHost: String?
    /// Why adopting the household server failed (unreachable, Seerr older than 3.4, …).
    @Published
    private(set) var adoptionError: Error?

    /// The first failure of the last couch sign-in (automatic or a press).
    @Published
    private(set) var signInFailure: SignInFailure?
    /// The couch is being signed in without a press: the sign-in screen shows no buttons.
    @Published
    private(set) var isSigningInAutomatically: Bool = false

    @Injected(\.seerrService)
    private var seerrService: SeerrService

    private let logger = Logger.swiftfin()
    private var cancellables: Set<AnyCancellable> = []
    private var isStarting = false
    /// Couches that were already signed in silently.
    private var silentlySignedInCouchIDs: Set<String> = []

    private var couch: CouchGroup? {
        Container.shared.currentUserSession()?.couch
    }

    /// The couch members (couch order) that can sign in with Quick Connect from here and have no session yet.
    var membersToSignIn: [UserState] {
        guard let couch else { return [] }

        return seerrService.couchMembersNeedingSignIn(couch)
    }

    /// The Jellyfin server of the current session, for avatars.
    var server: ServerState? {
        Container.shared.currentUserSession()?.server
    }

    /// Whether Discover should look for the household's server again by itself
    /// (returning to the app, selecting the tab): nothing is set up yet, or adopting failed.
    var shouldCheckAgain: Bool {
        phase == .needsServer || adoptionError != nil
    }

    init() {
        let service = Container.shared.seerrService()

        self.phase = Self.phase(
            hasServer: service.serverURL != nil,
            hasClient: service.client != nil
        )

        // `@Published` emits before the new value is stored: use the emitted values.
        Publishers.CombineLatest(
            service.$serverURL.map { $0 != nil },
            service.$client.map { $0 != nil }
        )
        .removeDuplicates { $0 == $1 }
        .sink { [weak self] hasServer, hasClient in
            self?.serviceDidChange(hasServer: hasServer, hasClient: hasClient)
        }
        .store(in: &cancellables)
    }

    // MARK: - Start

    /// Adopts (or follows) the household's Seerr server, then recomputes the phase.
    ///
    /// When Seerr already works here, the phase stays `ready` while the household is checked.
    /// When this just adopted the household's server (or adopted it earlier and nobody here ever
    /// had a Seerr session), the couch is signed in right away, unless someone explicitly signed out.
    func start() async {
        guard !isStarting else { return }

        isStarting = true
        defer { isStarting = false }

        if phase != .ready {
            phase = .checking
        }

        var didAdopt = false

        do {
            didAdopt = try await seerrService.adoptHouseholdServerIfNeeded() != nil
            adoptionError = nil
            attemptedHost = nil
        } catch is CancellationError {
            // Leave the state as it was
        } catch {
            logger.error(
                "Failed to adopt the household Seerr server",
                metadata: ["error": .string(error.localizedDescription)]
            )

            adoptionError = error
            let householdURL = await seerrService.householdServerURL()
            attemptedHost = householdURL.map { $0.host() ?? $0.absoluteString }
        }

        guard shouldSignInAutomatically(didAdopt: didAdopt) else {
            recomputePhase()
            return
        }

        logger.info("Seerr: signing the couch in with Quick Connect without a press")

        isSigningInAutomatically = true
        await signInCouch()
        isSigningInAutomatically = false
    }

    /// The zero-click sign-in: a server without anyone signed in, no explicit sign-out, and either
    /// the household's server was just adopted, or it was adopted earlier and nobody here ever had a session.
    private func shouldSignInAutomatically(didAdopt: Bool) -> Bool {
        guard seerrService.serverURL != nil,
              seerrService.client == nil,
              adoptionError == nil,
              !SeerrTVSetupFlags.isSignedOutExplicitly,
              membersToSignIn.isNotEmpty
        else { return false }

        if didAdopt {
            return true
        }

        return SeerrTVSetupFlags.isHouseholdAdopted
            && !SeerrTVSetupFlags.hadSession
            && seerrService.signedInUserIDs.isEmpty
    }

    // MARK: - Sign In

    /// A press on Sign in or Try again: also allows the zero-click sign-in again after an explicit sign-out.
    func signInCouchManually() async {
        SeerrTVSetupFlags.clearExplicitSignOut()

        await signInCouch()
    }

    /// Signs in every couch member that needs a session, one after the other.
    /// The first failure is shown through `signInFailure`; the others are only logged.
    func signInCouch() async {
        if case .signingIn = phase {
            return
        }

        let members = membersToSignIn

        guard members.isNotEmpty else {
            recomputePhase()
            return
        }

        signInFailure = nil

        for member in members {
            phase = .signingIn(member.username)

            do {
                try await seerrService.signInWithQuickConnect(jellyfinUserID: member.id)
            } catch is CancellationError {
                break
            } catch {
                logger.error(
                    "Failed to sign a couch member in to Seerr",
                    metadata: [
                        "jellyfinUserID": .string(member.id),
                        "error": .string(error.localizedDescription),
                    ]
                )

                if signInFailure == nil {
                    signInFailure = SignInFailure(
                        name: member.username,
                        message: error.localizedDescription
                    )
                }
            }
        }

        recomputePhase()
    }

    /// Signs in, in the background, couch members without a Seerr session (someone who joined the couch later).
    /// Best effort: once per couch while it succeeds; after a failure (logged only) the next appearance retries.
    func signInRemainingCouchSilently() {
        guard phase == .ready,
              !seerrService.hasAPIKey,
              let couch,
              !silentlySignedInCouchIDs.contains(couch.id),
              seerrService.couchMembersNeedingSignIn(couch).isNotEmpty
        else { return }

        silentlySignedInCouchIDs.insert(couch.id)

        let service = seerrService

        // `signInCouch(_:)` logs each failure; the phase follows the service by itself
        Task { @MainActor [weak self] in
            let failures = await service.signInCouch(couch)

            // Try again on the next appearance instead of never (e.g. a network hiccup)
            if failures.isNotEmpty {
                self?.silentlySignedInCouchIDs.remove(couch.id)
            }
        }
    }

    // MARK: - Phase

    private func serviceDidChange(hasServer: Bool, hasClient: Bool) {
        // A server was saved (e.g. entered in settings): an earlier adoption failure is no longer current
        if hasServer {
            adoptionError = nil
            attemptedHost = nil
        }

        if hasClient {
            SeerrTVSetupFlags.noteSession()
        }

        // `start()` and `signInCouch()` recompute when they finish
        guard phase != .checking else { return }

        if case .signingIn = phase {
            return
        }

        phase = Self.phase(hasServer: hasServer, hasClient: hasClient)
    }

    private func recomputePhase() {
        let hasClient = seerrService.client != nil

        if hasClient {
            SeerrTVSetupFlags.noteSession()
        }

        phase = Self.phase(
            hasServer: seerrService.serverURL != nil,
            hasClient: hasClient
        )
    }

    private static func phase(hasServer: Bool, hasClient: Bool) -> Phase {
        if hasClient {
            .ready
        } else if hasServer {
            .needsSignIn
        } else {
            .needsServer
        }
    }
}
