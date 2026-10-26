//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import FactoryKit
import JellyfinAPI
import SwiftUI

/// Chooses the quality, and for shows the seasons, to download.
struct DownloadOptionsView: View {

    @AppStorage("downloadQuality")
    private var quality: DownloadQuality = .original
    @AppStorage("downloadOnlyUnwatched")
    private var onlyUnwatched: Bool = false

    @InjectedObject(\.downloadManager)
    private var downloadManager

    @Router
    private var router

    @State
    private var seasons: [BaseItemDto] = []
    @State
    private var isLoadingSeasons = false
    /// The ID of what is being prepared, or the series ID for "Download All".
    @State
    private var startingID: String?
    @State
    private var error: Error?

    let item: BaseItemDto

    private var isCollection: Bool {
        item.type == .series || item.type == .season
    }

    /// The native player can't open containers like MKV, so only offer
    /// the original file when it is known to play.
    private var availableQualities: [DownloadQuality] {
        guard Defaults[.VideoPlayer.videoPlayerType] == .avPlayer else { return DownloadQuality.allCases }

        let container = item.mediaSources?.first?.container ?? ""
        let isNativeContainer = !isCollection && ["mp4", "m4v", "mov"].contains { container.contains($0) }

        return isNativeContainer ? DownloadQuality.allCases : DownloadQuality.allCases.filter(\.isTranscoded)
    }

    private func estimatedSize(for quality: DownloadQuality) -> String? {
        let mediaSource = item.mediaSources?.first

        let size = quality.estimatedSize(
            runtimeSeconds: item.runtime?.seconds ?? 0,
            sourceSize: mediaSource?.size,
            sourceBitrate: mediaSource?.bitrate
        )

        return size.map { Int64($0).formatted(.byteCount(style: .file)) }
    }

    private func start(_ item: BaseItemDto) {
        startingID = item.id

        Task { @MainActor in
            do {
                try await downloadManager.download(item, quality: quality, onlyUnplayed: onlyUnwatched)
                UIDevice.feedback(.success)
                router.dismiss()
            } catch {
                self.error = error
            }

            startingID = nil
        }
    }

    private func loadSeasons() async {
        guard item.type == .series, let seriesID = item.id,
              let userSession = Container.shared.currentUserSession()
        else { return }

        isLoadingSeasons = true
        defer { isLoadingSeasons = false }

        var parameters = Paths.GetSeasonsParameters()
        parameters.fields = [.childCount]
        parameters.isMissing = false
        parameters.userID = userSession.user.id

        do {
            let response = try await userSession.client.send(Paths.getSeasons(seriesID: seriesID, parameters: parameters))
            seasons = response.value.items ?? []
        } catch {
            self.error = error
        }
    }

    // MARK: - Body

    var body: some View {
        Form {
            qualitySection

            if isCollection {
                collectionSections
            } else {
                Section {
                    downloadButton(
                        title: L10n.Downloads.download,
                        id: item.id
                    ) {
                        start(item)
                    }
                } footer: {
                    availableSpaceFooter
                }
            }
        }
        .navigationTitle(item.displayTitle)
        .toolbarTitleDisplayMode(.inline)
        .navigationBarCloseButton {
            router.dismiss()
        }
        .interactiveDismissDisabled(startingID != nil)
        .disabled(startingID != nil)
        .onFirstAppear {
            if !availableQualities.contains(quality) {
                quality = .p1080
            }
        }
        .task {
            await loadSeasons()
        }
        .errorMessage($error)
    }

    // MARK: - Sections

    @ViewBuilder
    private var qualitySection: some View {
        Section {
            Picker(L10n.Downloads.quality, selection: $quality) {
                ForEach(availableQualities) { quality in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(quality.displayTitle)

                        if !isCollection, let size = estimatedSize(for: quality) {
                            Text(L10n.Downloads.estimatedSize(size))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(quality)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            Text(L10n.Downloads.quality)
        } footer: {
            Text(L10n.Downloads.qualityFooter)
        }
    }

    @ViewBuilder
    private var collectionSections: some View {
        Section {
            Toggle(L10n.Downloads.onlyUnwatched, isOn: $onlyUnwatched)
        }

        if item.type == .season {
            Section {
                downloadButton(title: L10n.Downloads.downloadSeason, id: item.id) {
                    start(item)
                }
            } footer: {
                availableSpaceFooter
            }
        } else {
            Section(L10n.Downloads.seasons) {
                if isLoadingSeasons {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }

                ForEach(seasons, id: \.id) { season in
                    Button {
                        start(season)
                    } label: {
                        LabeledContent {
                            if startingID == season.id {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.down.circle")
                                    .foregroundStyle(Color.accentColor)
                            }
                        } label: {
                            Text(season.displayTitle)
                                .foregroundStyle(.primary)

                            if let count = season.childCount {
                                Text(L10n.Downloads.episodeCount(count))
                            }
                        }
                    }
                }
            }

            if seasons.count > 1 {
                Section {
                    downloadButton(title: L10n.Downloads.downloadAll, id: item.id) {
                        start(item)
                    }
                } footer: {
                    availableSpaceFooter
                }
            }
        }
    }

    @ViewBuilder
    private func downloadButton(title: String, id: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Spacer()

                if startingID != nil, startingID == id {
                    ProgressView()
                } else {
                    Label(title, systemImage: "arrow.down.circle.fill")
                        .fontWeight(.semibold)
                }

                Spacer()
            }
        }
    }

    @ViewBuilder
    private var availableSpaceFooter: some View {
        let available = FileManager.default.availableStorage

        if available > 0 {
            Text(L10n.Downloads.availableSpace(Int64(available).formatted(.byteCount(style: .file))))
        }
    }
}
