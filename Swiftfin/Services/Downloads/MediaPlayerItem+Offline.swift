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
import JellyfinAPI
import UIKit

extension MediaPlayerItem {

    /// Builds a `MediaPlayerItem` that plays a downloaded file, without contacting the server.
    static func buildOffline(
        for record: DownloadRecord,
        modifyItem: ((inout BaseItemDto) -> Void)? = nil
    ) throws -> MediaPlayerItem {

        let downloadManager = Container.shared.downloadManager()

        guard let fileURL = downloadManager.mediaURL(for: record) else {
            throw ErrorMessage(L10n.Downloads.fileMissing)
        }

        var item = record.playbackItem
        modifyItem?(&item)
        item.runTimeTicks = record.mediaSource.runTimeTicks ?? item.runTimeTicks

        let imageURL = downloadManager.imageURL(for: record)

        let deviceProfile = DeviceProfile.build(
            for: Defaults[.VideoPlayer.videoPlayerType],
            compatibilityMode: Defaults[.VideoPlayer.Playback.compatibilityMode]
        )

        let playbackItem = MediaPlayerItem(
            baseItem: item,
            mediaSource: record.mediaSource,
            playSessionID: UUID().uuidString,
            url: fileURL,
            deviceProfile: deviceProfile,
            thumbnailProvider: {
                guard let imageURL else { return nil }

                return UIImage(contentsOfFile: imageURL.path(percentEncoded: false))
            },
            isOffline: true
        )

        playbackItem.observers.append(OfflineProgressObserver(itemID: record.id))

        return playbackItem
    }
}

extension MediaPlayerItemProvider {

    /// A provider that plays a downloaded item.
    @MainActor
    static func offline(_ record: DownloadRecord) -> MediaPlayerItemProvider {
        MediaPlayerItemProvider(
            item: record.playbackItem,
            mediaSource: record.mediaSource
        ) { _, modifyItem in
            try await MediaPlayerItem.buildOffline(for: record, modifyItem: modifyItem)
        }
    }
}

/// Saves the playback position of a downloaded item on the device,
/// so it resumes offline and can be synced to the server later.
@MainActor
final class OfflineProgressObserver: MediaPlayerObserver {

    weak var manager: MediaPlayerManager? {
        didSet {
            if let manager {
                setup(with: manager)
            }
        }
    }

    private let itemID: String
    private var cancellables: Set<AnyCancellable> = []

    init(itemID: String) {
        self.itemID = itemID
    }

    private func setup(with manager: MediaPlayerManager) {
        cancellables = []

        Timer.publish(every: 10, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.save() }
            .store(in: &cancellables)

        manager.$playbackRequestStatus
            .dropFirst()
            .sink { [weak self] _ in self?.save() }
            .store(in: &cancellables)

        manager.actions
            .sink { [weak self] action in
                guard let self else { return }

                switch action {
                case .stop, .ended:
                    self.save()
                    self.cancellables = []

                    Task {
                        await Container.shared.downloadManager().syncPlaybackProgress()
                    }

                default: ()
                }
            }
            .store(in: &cancellables)

        Notifications[.applicationDidEnterBackground]
            .publisher
            .sink { [weak self] _ in self?.save() }
            .store(in: &cancellables)
    }

    private func save() {
        guard let manager,
              manager.playbackItem?.baseItem.id == itemID,
              manager.seconds > .zero
        else { return }

        Container.shared.downloadManager().savePlaybackProgress(
            itemID: itemID,
            position: manager.seconds,
            runtime: manager.item.runtime
        )
    }
}
