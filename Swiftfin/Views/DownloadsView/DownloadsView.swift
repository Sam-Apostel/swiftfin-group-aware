//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import JellyfinAPI
import SwiftUI

/// Everything downloaded to the device. Works without a connection to the server.
struct DownloadsView: View {

    private struct SeriesGroup: Identifiable {
        let id: String
        let title: String
        let records: [DownloadRecord]
    }

    @InjectedObject(\.downloadManager)
    private var downloadManager

    @Router
    private var router

    @State
    private var isPresentingDeleteAll = false

    private var inProgress: [DownloadRecord] {
        downloadManager.records.values
            .filter { $0.status != .completed }
            .sorted { $0.dateAdded < $1.dateAdded }
    }

    private var movies: [DownloadRecord] {
        downloadManager.records.values
            .filter { $0.status == .completed && $0.item.type != .episode }
            .sorted { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
    }

    private var series: [SeriesGroup] {
        let episodes = downloadManager.records.values
            .filter { $0.status == .completed && $0.item.type == .episode }

        return Dictionary(grouping: episodes) { $0.item.seriesID ?? $0.item.seriesName ?? "" }
            .map { id, records in
                SeriesGroup(
                    id: id,
                    title: records.first?.item.seriesName ?? L10n.Downloads.other,
                    records: records.sorted {
                        ($0.item.parentIndexNumber ?? 0, $0.item.indexNumber ?? 0)
                            < ($1.item.parentIndexNumber ?? 0, $1.item.indexNumber ?? 0)
                    }
                )
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private func select(_ record: DownloadRecord) {
        switch record.status {
        case .completed:
            router.route(to: .videoPlayer(provider: .offline(record)))
        case .failed:
            Task { try? await downloadManager.retry(record) }
        case .queued, .downloading: ()
        }
    }

    // MARK: - Body

    var body: some View {
        Group {
            if downloadManager.records.isEmpty {
                ContentUnavailableView(
                    L10n.Downloads.emptyTitle,
                    systemImage: "arrow.down.circle",
                    description: Text(L10n.Downloads.emptyDescription)
                )
            } else {
                list
            }
        }
        .navigationTitle(L10n.Downloads.title)
        .toolbar {
            if downloadManager.records.isNotEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu(L10n.menu, systemImage: "ellipsis") {
                        Button(L10n.Downloads.deleteAll, systemImage: "trash", role: .destructive) {
                            isPresentingDeleteAll = true
                        }
                    }
                }
            }
        }
        .confirmationDialog(
            L10n.Downloads.deleteAllConfirmation,
            isPresented: $isPresentingDeleteAll,
            titleVisibility: .visible
        ) {
            Button(L10n.Downloads.deleteAll, role: .destructive) {
                downloadManager.deleteAll()
            }

            Button(L10n.cancel, role: .cancel) {}
        }
        .task {
            await downloadManager.syncPlaybackProgress()
        }
    }

    @ViewBuilder
    private var list: some View {
        List {
            if inProgress.isNotEmpty {
                Section(L10n.Downloads.downloading) {
                    ForEach(inProgress) { record in
                        row(for: record)
                    }
                }
            }

            if movies.isNotEmpty {
                Section(L10n.Downloads.movies) {
                    ForEach(movies) { record in
                        row(for: record)
                    }
                }
            }

            ForEach(series) { group in
                Section(group.title) {
                    ForEach(group.records) { record in
                        row(for: record)
                    }
                }
            }

            Section {} footer: {
                Text(L10n.Downloads.storageUsed(downloadManager.totalBytesUsed.formatted(.byteCount(style: .file))))
            }
        }
    }

    @ViewBuilder
    private func row(for record: DownloadRecord) -> some View {
        Button {
            select(record)
        } label: {
            DownloadRow(record: record, imageURL: downloadManager.imageURL(for: record))
        }
        .foregroundStyle(.primary)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(L10n.Downloads.delete, systemImage: "trash", role: .destructive) {
                downloadManager.delete(record)
            }
        }
        .contextMenu {
            if record.status == .failed {
                Button(L10n.Downloads.retry, systemImage: "arrow.clockwise") {
                    Task { try? await downloadManager.retry(record) }
                }
            }

            Button(L10n.Downloads.delete, systemImage: "trash", role: .destructive) {
                downloadManager.delete(record)
            }
        }
    }
}

// MARK: - Row

private struct DownloadRow: View {

    let record: DownloadRecord
    let imageURL: URL?

    private var subtitle: String? {
        if record.item.type == .episode {
            return [record.item.seasonEpisodeLabel, record.item.seriesName]
                .compactMap { $0 }
                .joined(separator: " · ")
        }

        return record.item.productionYear.map { String($0) }
    }

    private var image: UIImage? {
        guard let imageURL else { return nil }

        return UIImage(contentsOfFile: imageURL.path(percentEncoded: false))
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Rectangle()
                    .fill(Color.secondarySystemFill)

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: record.item.type == .episode ? "tv" : "film")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: record.item.type == .episode ? 96 : 54, height: record.item.type == .episode ? 54 : 81)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(record.displayTitle)
                    .font(.headline)
                    .lineLimit(2)

                if let subtitle, subtitle.isNotEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                status
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var status: some View {
        switch record.status {
        case .completed:
            HStack(spacing: 6) {
                Text(record.bytesWritten.formatted(.byteCount(style: .file)))

                Text(record.quality.displayTitle)

                if let ticks = record.playbackPositionTicks, ticks > 0, let runtime = record.item.runTimeTicks, runtime > 0 {
                    ProgressView(value: Double(ticks), total: Double(runtime))
                        .frame(width: 40)
                }

                if record.isPlayed == true {
                    Image(systemName: "checkmark.circle.fill")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

        case .queued:
            Text(L10n.Downloads.queued)
                .font(.caption)
                .foregroundStyle(.secondary)

        case .downloading:
            VStack(alignment: .leading, spacing: 2) {
                ProgressView(value: record.progress ?? 0)

                if let expected = record.bytesExpected {
                    let written = record.bytesWritten.formatted(.byteCount(style: .file))
                    let total = expected.formatted(.byteCount(style: .file))

                    Text(L10n.Downloads.progress(written, total))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

        case .failed:
            Label(record.errorMessage ?? L10n.Downloads.failed, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .lineLimit(2)
        }
    }
}
