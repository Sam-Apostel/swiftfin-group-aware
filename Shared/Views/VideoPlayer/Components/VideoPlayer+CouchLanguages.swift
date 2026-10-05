//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension View {

    /// Shows the couch's language pick as an overlay toast when a new item starts,
    /// e.g. "Dutch audio · no subtitles — Tuur is on the couch".
    ///
    /// - Only items built with a couch decision announce. Rebuilds after a track or
    ///   bitrate change carry no decision, so they stay silent.
    /// - A summary is only announced again when it differs from the last one
    ///   announced in this player, so autoplaying a series doesn't repeat it every episode.
    /// - The toast waits for the first frames: it appears once the playback position moves
    ///   forward (or after 5 seconds), and stays long enough to read from the couch.
    func couchLanguageAnnouncements(manager: MediaPlayerManager, toastProxy: ToastProxy) -> some View {
        modifier(
            CouchLanguageAnnouncementModifier(
                manager: manager,
                toastProxy: toastProxy
            )
        )
    }
}

private struct CouchLanguageAnnouncementModifier: ViewModifier {

    @StateObject
    private var announcer = CouchLanguageAnnouncer()

    private let manager: MediaPlayerManager
    private let toastProxy: ToastProxy

    init(manager: MediaPlayerManager, toastProxy: ToastProxy) {
        self.manager = manager
        self.toastProxy = toastProxy
    }

    func body(content: Content) -> some View {
        content
            .onReceive(manager.$playbackItem) { newItem in
                announcer.itemDidChange(
                    summary: newItem?.couchLanguageDecision?.summary,
                    toastProxy: toastProxy
                )
            }
            .onReceive(manager.secondsBox.$value) { seconds in
                announcer.secondsDidChange(seconds)
            }
            .onReceive(manager.$state) { newState in
                if newState == .stopped || newState == .error {
                    announcer.dropPending()
                }
            }
            .onDisappear {
                announcer.dropPending()
            }
    }
}

/// Holds the couch language summary until the first frames play, then presents it.
///
/// A reference type, so item, position and state events that arrive in the same
/// run loop see each other's changes immediately.
@MainActor
private final class CouchLanguageAnnouncer: ObservableObject {

    /// Long enough to read from the couch. Other toasts keep their default duration.
    private static var toastDuration: TimeInterval {
        #if os(tvOS)
        return 6
        #else
        return 4
        #endif
    }

    /// Present anyway when the playback position hasn't moved forward by then.
    private static let fallbackDelay: Duration = .seconds(5)

    private var lastSummary: String?
    private var pendingSummary: String?
    /// The first position seen after the item changed: playback has started once the position moves past it.
    private var baselineSeconds: Duration?
    private weak var toastProxy: ToastProxy?
    private var fallbackTask: Task<Void, Never>?

    func itemDidChange(summary: String?, toastProxy: ToastProxy) {
        guard let summary, summary != lastSummary, summary != pendingSummary else { return }

        self.toastProxy = toastProxy
        pendingSummary = summary
        baselineSeconds = nil

        fallbackTask?.cancel()
        fallbackTask = Task { [weak self] in
            try? await Task.sleep(for: Self.fallbackDelay)

            guard !Task.isCancelled else { return }

            self?.presentPending()
        }
    }

    func secondsDidChange(_ seconds: Duration) {
        guard pendingSummary != nil else { return }
        guard let baselineSeconds else {
            baselineSeconds = seconds
            return
        }

        if seconds > baselineSeconds {
            presentPending()
        }
    }

    /// Playback stopped, failed or the player closed: the summary is no longer worth showing.
    func dropPending() {
        pendingSummary = nil
        baselineSeconds = nil
        fallbackTask?.cancel()
        fallbackTask = nil
    }

    private func presentPending() {
        guard let summary = pendingSummary else { return }

        let toastProxy = toastProxy
        dropPending()
        lastSummary = summary

        toastProxy?.present(summary, systemName: "sofa.fill", duration: Self.toastDuration)
    }
}
