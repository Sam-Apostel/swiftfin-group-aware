//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import Logging
import UIKit

/// A tiny client for T-Minus' ingest API, with the same request shapes as TMinusKit
/// (`POST /feedback`, `POST /errors`, `POST /heartbeat`), sent with the report-only key.
///
/// Reporting never throws into the app, except `sendFeedback`, which someone is waiting on.
enum TMinusClient {

    enum FeedbackKind: String, Codable, CaseIterable {
        case bug
        case feature
    }

    enum FeedbackResult {
        /// Delivered to T-Minus.
        case sent
        /// Offline: saved, and sent on the next launch.
        case saved
    }

    enum ClientError: Error {
        case http(Int)
    }

    struct Feedback: Codable {
        let kind: FeedbackKind
        let title: String
        let body: String?
    }

    private struct ErrorEvent: Encodable {
        let message: String
        let type: String?
        let level: String
        let fingerprint: String?
        let culprit: String?
        let release: String?
        let environment: String?
        let extra: [String: String]?
    }

    private struct Heartbeat: Encodable {
        let summary: String
    }

    private static let logger = Logger.swiftfin()

    private static let lastHeartbeatKey = "tminus.lastHeartbeat"

    private static let pendingFeedbackURL: URL? = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)
        .first?
        .appendingPathComponent("tminus-pending-feedback.json")

    private static let pendingLock = NSLock()

    /// "1.4.1 (202611021200)", like TMinusKit's default release.
    static var release: String? {
        guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else { return nil }

        if let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
            return "\(version) (\(build))"
        }
        return version
    }

    static var environment: String {
        #if DEBUG
        "debug"
        #else
        "release"
        #endif
    }

    // MARK: - Launch

    /// Sends a heartbeat at most once a day and retries reports saved while offline.
    static func launch() {
        Task.detached(priority: .utility) {
            await TMinusClient.sendDailyHeartbeat()
            await TMinusClient.flushPendingFeedback()
        }
    }

    private static func sendDailyHeartbeat() async {
        let defaults = UserDefaults.appSuite

        if let last = defaults.object(forKey: lastHeartbeatKey) as? Date, Calendar.current.isDateInToday(last) {
            return
        }

        let platform = await MainActor.run { UIDevice.platform }
        let summary = "Couchfin \(release ?? "?") on \(platform)"

        do {
            try await post("heartbeat", Heartbeat(summary: summary))
            defaults.set(Date.now, forKey: lastHeartbeatKey)
        } catch {
            logger.debug("T-Minus heartbeat not sent: \(error.localizedDescription)")
        }
    }

    // MARK: - Feedback

    /// Sends a problem report or idea; it lands in the T-Minus inbox. Saved for later when offline.
    static func sendFeedback(_ feedback: Feedback) async throws -> FeedbackResult {
        do {
            try await post("feedback", feedback)
            return .sent
        } catch let error as URLError where isOffline(error) {
            savePending(feedback)
            return .saved
        }
    }

    private static func isOffline(_ error: URLError) -> Bool {
        let offlineCodes: [URLError.Code] = [
            .notConnectedToInternet,
            .networkConnectionLost,
            .timedOut,
            .cannotFindHost,
            .cannotConnectToHost,
            .dnsLookupFailed,
            .dataNotAllowed,
            .internationalRoamingOff,
        ]
        return offlineCodes.contains(error.code)
    }

    private static func savePending(_ feedback: Feedback) {
        pendingLock.lock()
        defer { pendingLock.unlock() }

        let pending = readPending() + [feedback]
        writePending(Array(pending.suffix(10)))
    }

    /// One retry per launch: whatever is still offline stays saved, anything the server refused is dropped.
    private static func flushPendingFeedback() async {
        pendingLock.lock()
        let pending = readPending()
        writePending([])
        pendingLock.unlock()

        for feedback in pending {
            do {
                try await post("feedback", feedback)
            } catch let error as URLError where isOffline(error) {
                savePending(feedback)
            } catch {
                logger.error("Dropping a saved problem report: \(error.localizedDescription)")
            }
        }
    }

    private static func readPending() -> [Feedback] {
        guard let pendingFeedbackURL, let data = try? Data(contentsOf: pendingFeedbackURL) else { return [] }

        return (try? JSONDecoder().decode([Feedback].self, from: data)) ?? []
    }

    private static func writePending(_ feedback: [Feedback]) {
        guard let pendingFeedbackURL else { return }

        if feedback.isEmpty {
            try? FileManager.default.removeItem(at: pendingFeedbackURL)
        } else if let data = try? JSONEncoder().encode(feedback) {
            try? data.write(to: pendingFeedbackURL, options: .atomic)
        }
    }

    // MARK: - Errors

    /// Reports an unexpected error. Fire-and-forget.
    static func captureError(
        _ error: Error,
        culprit: String,
        extra: [String: String]? = nil
    ) {
        let errorType = String(reflecting: type(of: error))
        let nsError = error as NSError
        var message = error.localizedDescription

        if message.isEmpty {
            message = "\(nsError.domain) \(nsError.code)"
        }

        let event = ErrorEvent(
            message: message,
            type: errorType,
            level: "error",
            // The same error case groups together whatever its message says.
            fingerprint: "\(culprit)|\(errorType)|\(nsError.domain)|\(nsError.code)",
            culprit: culprit,
            release: release,
            environment: environment,
            extra: extra
        )

        Task.detached(priority: .utility) {
            do {
                try await TMinusClient.post("errors", event)
            } catch {
                TMinusClient.logger.debug("T-Minus error report not sent: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Requests

    private static func post(_ path: String, _ body: some Encodable) async throws {
        var request = URLRequest(url: TMinusConfig.ingestURL.appendingPathComponent(path), timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("Bearer \(TMinusConfig.reportKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (_, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        guard (200 ..< 300).contains(status) else {
            throw ClientError.http(status)
        }
    }
}
