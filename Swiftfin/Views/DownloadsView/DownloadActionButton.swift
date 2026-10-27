//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import SwiftUI

extension ItemActionButtons {

    /// Downloads the item for offline playback, or removes its download.
    struct Download: View {

        @EnvironmentObject
        private var provider: ItemContentGroupProvider

        @InjectedObject(\.downloadManager)
        private var downloadManager

        @Router
        private var router

        static func isAvailable(for provider: ItemContentGroupProvider) -> Bool {
            provider.item.presentPlayButton && DownloadManager.canDownload(provider.item)
        }

        private var isCollection: Bool {
            provider.item.type == .series || provider.item.type == .season
        }

        var body: some View {
            if isCollection {
                Button(
                    provider.item.type == .season ? L10n.Downloads.downloadSeason : L10n.Downloads.download,
                    systemImage: "arrow.down.circle"
                ) {
                    router.route(to: .downloadOptions(item: provider.item))
                }
            } else if let record = downloadManager.record(for: provider.item.id) {
                switch record.status {
                case .completed:
                    Button(
                        L10n.Downloads.removeDownload,
                        systemImage: "trash",
                        role: .destructive
                    ) {
                        downloadManager.delete(record)
                    }

                case .queued, .downloading:
                    Button(
                        L10n.Downloads.cancelDownload,
                        systemImage: "xmark.circle",
                        role: .destructive
                    ) {
                        downloadManager.delete(record)
                    }

                case .failed:
                    Button(
                        L10n.Downloads.retry,
                        systemImage: "arrow.clockwise"
                    ) {
                        Task { try? await downloadManager.retry(record) }
                    }
                }
            } else {
                Button(
                    L10n.Downloads.download,
                    systemImage: "arrow.down.circle"
                ) {
                    router.route(to: .downloadOptions(item: provider.item))
                }
                .disabled(downloadManager.isPreparing(provider.item.id))
            }
        }
    }
}
