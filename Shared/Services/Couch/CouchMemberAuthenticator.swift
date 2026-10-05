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
import SwiftUI

/// Confirms the people who are about to start a couch, one at a time.
///
/// - Each member's local access policy (PIN, or Face ID / passcode on iOS) is asked in pick order,
///   with a short gap between prompts, since only one prompt can be presented at a time.
/// - A PIN gets up to `maximumPinTries` tries; after a wrong one the prompt reads
///   "Wrong PIN for Lisa — try again".
/// - After the last wrong PIN, or a cancel, it asks "Start without Lisa?". Members already
///   confirmed are kept, so nobody types their PIN twice.
/// - A member without a stored sign-in is offered the same way ("Lisa needs to sign in again"),
///   before anyone is asked for a PIN.
///
/// The dialogs are presented by `.couchMemberAuthenticatorPrompts(_:)`, which the view that owns
/// this object must attach (inside `WithLocalUserAuthentication`).
///
/// Used by the picker (`SelectUserView.startCouch`) and the couch switcher (#52).
@MainActor
final class CouchMemberAuthenticator: ObservableObject {

    /// The members that may start the couch.
    struct Result: Equatable {
        /// The confirmed member ids, in pick order. Never empty.
        let memberIDs: [String]
        /// Whether a grown-up (not `isRestricted`) proved who they are with a stored PIN
        /// (or device authentication on iOS) during this run.
        let verifiedGrownUp: Bool
    }

    /// Why a member can't be confirmed.
    enum SkipReason: Equatable {
        /// Wrong PIN `maximumPinTries` times.
        case wrongPin
        /// The PIN or Face ID prompt was cancelled or failed.
        case cancelled
        /// No stored access token: the member needs to sign in again.
        case needsSignIn
    }

    /// A dialog waiting for an answer.
    struct Prompt: Identifiable {

        enum Kind: Equatable {
            /// "Start without Lisa?" with "Start without Lisa" / Cancel.
            case startWithout(name: String, reason: SkipReason)
            /// The honest "Are you a grown-up?" confirmation, when no grown-up can prove it on this device.
            case grownUpConfirmation
        }

        let id: UUID
        let kind: Kind
        fileprivate let continuation: CheckedContinuation<Bool, Never>
    }

    static let maximumPinTries = 3

    /// The time a dismissed prompt or dialog needs before the next one can be presented.
    static let promptGap: TimeInterval = 0.6

    @Published
    private(set) var prompt: Prompt?

    @Injected(\.keychainService)
    private var keychain: KeychainSwift

    private var lastPresentationEnd: Date?

    private let logger = Logger.swiftfin()

    init() {}

    // MARK: - Members

    /// Asks every member's local access policy, one at a time, in pick order.
    ///
    /// - Parameters:
    ///   - members: the people on the couch, in pick order.
    ///   - authenticationAction: the environment's `localUserAuthenticationAction`. Without it, members
    ///     with a PIN or Face ID can't be confirmed and are offered to be left out.
    /// - Returns: the confirmed members, in pick order.
    /// - Throws: `CancellationError` when someone chose Cancel (show nothing), or an `ErrorMessage`
    ///   when the only person left can't be confirmed (wrong PIN, or no stored sign-in).
    func authenticate(
        _ members: [UserState],
        authenticationAction: LocalUserAuthenticationAction?
    ) async throws -> Result {
        let members = Self.unique(members)
        var skippedIDs: Set<String> = []

        // Ask about missing sign-ins first, so nobody types a PIN for a start that is then cancelled
        for member in members where member.storedAccessToken == nil {
            try await offerToSkip(
                member,
                reason: .needsSignIn,
                in: members,
                skippedIDs: skippedIDs,
                confirmedIDs: []
            )
            skippedIDs.insert(member.id)
        }

        var confirmedIDs: [String] = []
        var verifiedGrownUp = false

        for member in members where !skippedIDs.contains(member.id) {
            switch try await verify(member, authenticationAction: authenticationAction) {
            case let .confirmed(isProof):
                confirmedIDs.append(member.id)

                if isProof, !member.isRestricted {
                    verifiedGrownUp = true
                }

            case let .skipped(reason):
                try await offerToSkip(
                    member,
                    reason: reason,
                    in: members,
                    skippedIDs: skippedIDs,
                    confirmedIDs: confirmedIDs
                )
                skippedIDs.insert(member.id)
            }
        }

        guard confirmedIDs.isNotEmpty else { throw CancellationError() }

        return Result(memberIDs: confirmedIDs, verifiedGrownUp: verifiedGrownUp)
    }

    /// Whether `pin` is the stored PIN of a user that requires one.
    ///
    /// The same rule as `SelectUserViewModel.validatePin`: a user without a PIN policy,
    /// or without a PIN in the keychain, accepts any PIN.
    static func isValidPin(_ pin: String, for user: UserState) -> Bool {
        guard user.accessPolicy == .requirePin,
              let storedPin = Container.shared.keychainService().get("\(user.id)-pin")
        else { return true }

        return pin == storedPin
    }

    // MARK: - Grown-up check

    /// Runs `CouchGrownUpCheck` and, when no grown-up can prove it on this device,
    /// the honest "Are you a grown-up?" confirmation.
    ///
    /// - Parameters:
    ///   - grownUps: the stored users of the server, couch members first. Restricted users are ignored.
    ///   - authenticationAction: the environment's `localUserAuthenticationAction`.
    /// - Returns: whether a grown-up confirmed. `false` for a cancel, wrong PINs, or a cancelled task.
    func confirmGrownUp(
        grownUps: [UserState],
        authenticationAction: LocalUserAuthenticationAction?
    ) async -> Bool {
        do {
            try await waitForPresentationGap()
        } catch {
            return false
        }

        let outcome = await CouchGrownUpCheck.run(
            grownUps: grownUps,
            authenticationAction: authenticationAction
        )

        switch outcome {
        case .verified:
            lastPresentationEnd = .now
            return true

        case .declined:
            lastPresentationEnd = .now
            return false

        case .needsConfirmation:
            do {
                return try await ask(.grownUpConfirmation)
            } catch {
                return false
            }
        }
    }

    // MARK: - Presentation

    /// Answers the dialog with the given id. Answering an older or unknown dialog does nothing.
    func answer(_ promptID: UUID, accepted: Bool) {
        guard let prompt, prompt.id == promptID else { return }

        self.prompt = nil
        lastPresentationEnd = .now
        prompt.continuation.resume(returning: accepted)
    }

    /// Call after something else was dismissed (e.g. a context menu) right before starting,
    /// so the first prompt waits until it is gone.
    func didDismissPresentation() {
        lastPresentationEnd = .now
    }

    // MARK: - Private

    private enum Verification {
        /// `isProof`: a stored PIN or device authentication was checked, not just an open account.
        case confirmed(isProof: Bool)
        case skipped(SkipReason)
    }

    private static func unique(_ members: [UserState]) -> [UserState] {
        var seenIDs: Set<String> = []
        return members.filter { seenIDs.insert($0.id).inserted }
    }

    private func verify(
        _ member: UserState,
        authenticationAction: LocalUserAuthenticationAction?
    ) async throws -> Verification {
        let policy = member.accessPolicy

        switch policy {
        case .none:
            return .confirmed(isProof: false)

        case .requireDeviceAuthentication:
            guard let authenticationAction else { return .skipped(.cancelled) }

            try await waitForPresentationGap()

            do {
                _ = try await authenticationAction(
                    policy: policy,
                    reason: policy.authenticateReason(user: member)
                )
                lastPresentationEnd = .now

                #if os(iOS)
                return .confirmed(isProof: true)
                #else
                return .confirmed(isProof: false)
                #endif
            } catch {
                lastPresentationEnd = .now
                try Task.checkCancellation()

                logger.warning("Couch start: device authentication failed for \(member.id)")
                return .skipped(.cancelled)
            }

        case .requirePin:
            guard let authenticationAction else { return .skipped(.cancelled) }

            let hasStoredPin = keychain.get("\(member.id)-pin")?.isNotEmpty ?? false
            var reason = policy.authenticateReason(user: member)

            for _ in 1 ... Self.maximumPinTries {
                try await waitForPresentationGap()

                do {
                    let evaluated = try await authenticationAction(policy: .requirePin, reason: reason)
                    lastPresentationEnd = .now

                    let pin = (evaluated as? PinEvaluatedUserAccessPolicy)?.pin ?? ""

                    if Self.isValidPin(pin, for: member) {
                        return .confirmed(isProof: hasStoredPin)
                    }
                } catch is CancellationError {
                    lastPresentationEnd = .now
                    try Task.checkCancellation()

                    return .skipped(.cancelled)
                } catch {
                    // An invalid PIN (wrong length) counts as a wrong try
                    lastPresentationEnd = .now
                }

                reason = L10n.CouchStart.wrongPin(member.username)
            }

            return .skipped(.wrongPin)
        }
    }

    /// Asks "Start without Lisa?" and returns when the answer is yes.
    ///
    /// - Throws: `CancellationError` for Cancel. When nobody else would be left on the couch,
    ///   there is nothing to start without them: a wrong PIN or a missing sign-in throws an
    ///   `ErrorMessage` instead, and a cancelled prompt a `CancellationError`.
    private func offerToSkip(
        _ member: UserState,
        reason: SkipReason,
        in members: [UserState],
        skippedIDs: Set<String>,
        confirmedIDs: [String]
    ) async throws {
        let hasOthers = members.contains { other in
            other.id != member.id && !skippedIDs.contains(other.id)
        }

        guard hasOthers || confirmedIDs.isNotEmpty else {
            switch reason {
            case .wrongPin:
                throw ErrorMessage(L10n.incorrectPinForUser(member.username))
            case .needsSignIn:
                throw ErrorMessage(L10n.CouchStart.needsSignIn(member.username))
            case .cancelled:
                throw CancellationError()
            }
        }

        let accepted = try await ask(.startWithout(name: member.username, reason: reason))

        guard accepted else { throw CancellationError() }

        logger.info("Couch start: starting without \(member.id) (\(String(describing: reason)))")
    }

    /// Presents a dialog and waits for its answer.
    private func ask(_ kind: Prompt.Kind) async throws -> Bool {
        try await waitForPresentationGap()

        // Only one dialog at a time: an older one counts as cancelled
        if let prompt {
            answer(prompt.id, accepted: false)
        }

        let promptID = UUID()

        let accepted = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                prompt = Prompt(id: promptID, kind: kind, continuation: continuation)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.answer(promptID, accepted: false)
            }
        }

        try Task.checkCancellation()

        return accepted
    }

    private func waitForPresentationGap() async throws {
        guard let lastPresentationEnd else { return }

        let remaining = Self.promptGap - Date.now.timeIntervalSince(lastPresentationEnd)

        guard remaining > 0 else { return }

        try await Task.sleep(for: .milliseconds(Int(remaining * 1000)))
    }
}

// MARK: - Dialogs

extension View {

    /// Presents the dialogs of a `CouchMemberAuthenticator`: "Start without Lisa?" and the
    /// honest "Are you a grown-up?" confirmation.
    func couchMemberAuthenticatorPrompts(_ authenticator: CouchMemberAuthenticator) -> some View {
        modifier(CouchMemberAuthenticatorPromptsModifier(authenticator: authenticator))
    }
}

private struct CouchMemberAuthenticatorPromptsModifier: ViewModifier {

    @ObservedObject
    var authenticator: CouchMemberAuthenticator

    private struct StartWithout {
        let id: UUID
        let name: String
        let reason: CouchMemberAuthenticator.SkipReason
    }

    private var startWithout: StartWithout? {
        guard let prompt = authenticator.prompt,
              case let .startWithout(name, reason) = prompt.kind
        else { return nil }

        return StartWithout(id: prompt.id, name: name, reason: reason)
    }

    private var grownUpConfirmationID: UUID? {
        guard let prompt = authenticator.prompt, prompt.kind == .grownUpConfirmation else { return nil }

        return prompt.id
    }

    /// Presented while `id` is set. A dismissal without a button (e.g. Menu on the Siri Remote)
    /// answers no, one run loop later, so a button tapped in the same update answers first.
    private func isPresented(_ id: UUID?) -> Binding<Bool> {
        Binding(
            get: { id != nil },
            set: { isPresented in
                guard !isPresented, let id else { return }

                Task { @MainActor in
                    authenticator.answer(id, accepted: false)
                }
            }
        )
    }

    private func message(_ startWithout: StartWithout) -> String {
        switch startWithout.reason {
        case .wrongPin:
            L10n.CouchStart.wrongPinMessage(startWithout.name, tries: CouchMemberAuthenticator.maximumPinTries)
        case .cancelled:
            L10n.CouchStart.cancelledMessage(startWithout.name)
        case .needsSignIn:
            L10n.CouchStart.needsSignInMessage(startWithout.name)
        }
    }

    func body(content: Content) -> some View {
        let startWithout = startWithout
        let grownUpConfirmationID = grownUpConfirmationID

        return content
            .alert(
                L10n.CouchStart.startWithoutTitle(startWithout?.name ?? ""),
                isPresented: isPresented(startWithout?.id),
                presenting: startWithout
            ) { startWithout in
                Button(L10n.CouchStart.startWithout(startWithout.name)) {
                    authenticator.answer(startWithout.id, accepted: true)
                }

                Button(L10n.cancel, role: .cancel) {
                    authenticator.answer(startWithout.id, accepted: false)
                }
            } message: { startWithout in
                Text(message(startWithout))
            }
            .confirmationDialog(
                L10n.GrownUpCheck.confirmationTitle,
                isPresented: isPresented(grownUpConfirmationID),
                titleVisibility: .visible
            ) {
                Button(L10n.GrownUpCheck.confirm) {
                    if let grownUpConfirmationID {
                        authenticator.answer(grownUpConfirmationID, accepted: true)
                    }
                }

                Button(L10n.cancel, role: .cancel) {
                    if let grownUpConfirmationID {
                        authenticator.answer(grownUpConfirmationID, accepted: false)
                    }
                }
            } message: {
                Text(L10n.GrownUpCheck.noPinMessage)
            }
            .onDisappear {
                if let prompt = authenticator.prompt {
                    authenticator.answer(prompt.id, accepted: false)
                }
            }
    }
}
