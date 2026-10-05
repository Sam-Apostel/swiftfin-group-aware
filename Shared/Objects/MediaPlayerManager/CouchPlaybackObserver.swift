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
import JellyfinAPI

/// A playback event that is mirrored to every other member on the couch.
struct CouchPlaybackEvent {

    typealias Kind = CouchEchoPlan.EventKind

    let kind: Kind
    let itemID: String
    let itemName: String
    let positionTicks: Int
    let runtimeTicks: Int?
    let isPaused: Bool

    /// Whether this stop ends playback that failed, for example a stream or transcode error.
    ///
    /// Jellyfin closes a failed session without touching user data, and the echo never
    /// writes user data for it either.
    var isFailed: Bool = false

    /// The fraction of the runtime that has been watched, if the runtime is known.
    var playedFraction: Double? {
        guard let runtimeTicks, runtimeTicks > 0 else { return nil }

        return Double(positionTicks) / Double(runtimeTicks)
    }

    /// Whether this stop happened far enough into the item to count as played.
    ///
    /// Matches Jellyfin's default `MaxResumePct` of 90%.
    var didFinish: Bool {
        guard kind == .stop, !isFailed, let playedFraction else { return false }

        return playedFraction >= 0.9
    }

    /// The parts of this event that `CouchEchoPlan` decides on.
    var planEvent: CouchEchoPlan.Event {
        CouchEchoPlan.Event(
            kind: kind,
            positionTicks: positionTicks,
            didFinish: didFinish,
            isFailed: isFailed
        )
    }
}

extension Container {

    var couchPlaybackObserver: Factory<CouchPlaybackObserver> {
        self { @MainActor in CouchPlaybackObserver() }
            .singleton
    }
}

/// Observes the video player and forwards start, progress and stop events to
/// the current session's `CouchPlaybackService`, which echoes them to every
/// other member on the couch.
///
/// Attached once per player launch from `NavigationRoute.videoPlayer(manager:)`.
/// Does nothing when the couch is a single person.
@MainActor
final class CouchPlaybackObserver {

    /// How often progress is echoed while an item is playing or paused.
    private static let progressInterval: TimeInterval = 30

    private var cancellables = Set<AnyCancellable>()
    private var currentItem: BaseItemDto?
    private var lastPlaybackRequestStatus: MediaPlayerManager.PlaybackRequestStatus = .playing
    private var service: CouchPlaybackService?
    private weak var manager: MediaPlayerManager?

    func attach(to manager: MediaPlayerManager) {

        // A new player replaced one that never stopped: close out its item first.
        if let currentItem, let previousManager = self.manager, previousManager !== manager {
            emit(.stop, item: currentItem, seconds: previousManager.seconds)
        }

        cancellables = []
        currentItem = nil
        service = nil
        self.manager = nil

        guard let userSession = Container.shared.currentUserSession(),
              userSession.couch.isGroup,
              userSession.memberSessions.isNotEmpty
        else { return }

        self.manager = manager
        service = userSession.couchPlaybackService
        lastPlaybackRequestStatus = manager.playbackRequestStatus

        // `@Published` emits in `willSet`: `manager.seconds` still holds the previous item's position here.
        manager.$playbackItem
            .sink { [weak self, weak manager] newItem in
                guard let self, let manager else { return }

                self.playbackItemWillChange(to: newItem, manager: manager)
            }
            .store(in: &cancellables)

        manager.$playbackRequestStatus
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self, weak manager] newStatus in
                guard let self, let manager else { return }

                self.lastPlaybackRequestStatus = newStatus

                guard let item = self.currentItem else { return }

                self.emit(.progress, item: item, seconds: manager.seconds, isPaused: newStatus == .paused)
            }
            .store(in: &cancellables)

        Timer.publish(every: Self.progressInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self, weak manager] _ in
                guard let self, let manager, let item = self.currentItem else { return }

                self.emit(.progress, item: item, seconds: manager.seconds, isPaused: self.lastPlaybackRequestStatus == .paused)
            }
            .store(in: &cancellables)

        // Actions are published before the action runs, so `manager.seconds` is still valid on `.stop`.
        manager.actions
            .sink { [weak self, weak manager] action in
                guard let self, let manager else { return }

                switch action {
                case .stop:
                    self.stopObserving(manager: manager)
                case .error:
                    // The stream failed: close every member's session without writing their progress.
                    self.stopObserving(manager: manager, isFailed: true)
                case .playNewItem:
                    // Next episode, autoplay or a queue pick: close out the current item now,
                    // before the old player is stopped and the new item loads, which can move `seconds`.
                    self.stopCurrentItem(seconds: manager.seconds)
                default: ()
                }
            }
            .store(in: &cancellables)

        Notifications[.applicationWillTerminate]
            .publisher
            .sink { [weak self, weak manager] _ in
                guard let self, let manager else { return }

                self.stopObserving(manager: manager)
            }
            .store(in: &cancellables)
    }

    private func playbackItemWillChange(to newItem: MediaPlayerItem?, manager: MediaPlayerManager) {
        let newItemID = newItem?.baseItem.id

        // Track, bitrate and media source changes rebuild the playback item with the same id: ignore those.
        if let currentItem, currentItem.id != newItemID {
            stopCurrentItem(seconds: manager.seconds)
        }

        if let newItem, newItemID != nil, currentItem == nil {
            currentItem = newItem.baseItem
            emit(.start, item: newItem.baseItem, seconds: newItem.baseItem.startSeconds ?? .zero)
        }
    }

    /// Emits a stop for the current item, if any, and forgets it.
    private func stopCurrentItem(seconds: Duration, isFailed: Bool = false) {
        guard let currentItem else { return }

        self.currentItem = nil
        emit(.stop, item: currentItem, seconds: seconds, isFailed: isFailed)
    }

    private func stopObserving(manager: MediaPlayerManager, isFailed: Bool = false) {
        stopCurrentItem(seconds: manager.seconds, isFailed: isFailed)

        cancellables = []
        service = nil
        self.manager = nil
    }

    private func emit(
        _ kind: CouchPlaybackEvent.Kind,
        item: BaseItemDto,
        seconds: Duration,
        isPaused: Bool = false,
        isFailed: Bool = false
    ) {
        guard let itemID = item.id, !item.isLiveStream, let service else { return }

        let event = CouchPlaybackEvent(
            kind: kind,
            itemID: itemID,
            itemName: item.displayTitle,
            positionTicks: max(0, seconds.ticks),
            runtimeTicks: item.runTimeTicks,
            isPaused: isPaused,
            isFailed: isFailed
        )

        service.report(event)
    }
}
