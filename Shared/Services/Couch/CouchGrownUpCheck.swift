//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import Foundation
import KeychainSwift
import Logging

/// The one grown-up check, used before anything that loosens kid protection.
///
/// The first grown-up (not `isRestricted`) that is protected on this device answers:
/// - with a PIN, up to 3 tries, validated against the keychain like `SelectUserViewModel.validatePin`;
/// - on iOS, with device authentication (Face ID / passcode) when that is their sign-in policy.
///
/// PINs are per device, so a fresh Apple TV may have none: then the result is `.needsConfirmation`
/// and the caller shows a `confirmationDialog` (`L10n.GrownUpCheck.confirmationTitle`, `.confirm` / Cancel)
/// whose message states the limit (`L10n.GrownUpCheck.noPinMessage`).
@MainActor
enum CouchGrownUpCheck {

    enum Outcome {
        /// A grown-up proved it with their PIN or device authentication.
        case verified
        /// No grown-up is protected on this device: ask "I'm a grown-up" / Cancel.
        case needsConfirmation
        /// Cancelled, wrong PIN 3 times, or no way to ask.
        case declined
    }

    static let maximumPinTries = 3

    /// Asks the first protected grown-up to confirm.
    ///
    /// - Parameters:
    ///   - grownUps: the stored grown-ups of this server (members that are not `isRestricted`), couch members first.
    ///     Restricted users in the list are ignored.
    ///   - authenticationAction: the environment's `localUserAuthenticationAction`.
    ///     Without it a protected grown-up can't be asked, so the check is declined (fail closed).
    static func run(
        grownUps: [UserState],
        authenticationAction: LocalUserAuthenticationAction?
    ) async -> Outcome {
        guard let grownUp = grownUps.first(where: { !$0.isRestricted && isProtected($0) }) else {
            return .needsConfirmation
        }
        guard let authenticationAction else {
            Logger.swiftfin().warning("Grown-up check: no authentication action, declined")
            return .declined
        }

        switch grownUp.accessPolicy {
        case .requirePin:
            return await runPin(for: grownUp, authenticationAction: authenticationAction)

        case .requireDeviceAuthentication:
            do {
                _ = try await authenticationAction(
                    policy: .requireDeviceAuthentication,
                    reason: grownUp.accessPolicy.authenticateReason(user: grownUp)
                )
                return .verified
            } catch {
                return .declined
            }

        case .none:
            // Not reachable: `isProtected` is false for `.none`
            return .needsConfirmation
        }
    }

    /// The grown-ups (not `isRestricted`) that are not protected by a PIN
    /// (or device authentication on iOS) on this device.
    static func pinlessGrownUps(of users: [UserState]) -> [UserState] {
        users.filter { !$0.isRestricted && !isProtected($0) }
    }

    // MARK: - Private

    /// Whether this user can prove who they are on this device.
    ///
    /// A PIN policy only counts with a PIN in the keychain. Device authentication only exists on iOS.
    private static func isProtected(_ user: UserState) -> Bool {
        switch user.accessPolicy {
        case .none:
            return false
        case .requirePin:
            return storedPin(of: user) != nil
        case .requireDeviceAuthentication:
            #if os(iOS)
            return true
            #else
            return false
            #endif
        }
    }

    private static func storedPin(of user: UserState) -> String? {
        guard let pin = Container.shared.keychainService().get("\(user.id)-pin"), pin.isNotEmpty else { return nil }

        return pin
    }

    private static func runPin(
        for grownUp: UserState,
        authenticationAction: LocalUserAuthenticationAction
    ) async -> Outcome {
        guard let storedPin = storedPin(of: grownUp) else { return .declined }

        var reason = L10n.GrownUpCheck.enterPin(grownUp.username)

        for attempt in 1 ... maximumPinTries {
            if attempt > 1 {
                // Let the previous prompt dismiss before presenting the next one (as SelectUserView does)
                do {
                    try await Task.sleep(for: .milliseconds(600))
                } catch {
                    return .declined
                }
            }

            do {
                let evaluated = try await authenticationAction(policy: .requirePin, reason: reason)

                if let pinPolicy = evaluated as? PinEvaluatedUserAccessPolicy, pinPolicy.pin == storedPin {
                    return .verified
                }
            } catch is CancellationError {
                return .declined
            } catch {
                // An invalid PIN (wrong length) counts as a wrong try
            }

            reason = L10n.GrownUpCheck.wrongPin(grownUp.username, triesLeft: maximumPinTries - attempt)
        }

        return .declined
    }
}
