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

/// The audio and subtitle pickers of the item view, for use inside a `Menu`.
///
/// Used by the Playback menu's Tracks section and by the couch line under the
/// action buttons (`CouchLanguageLabel`), so both pick tracks the same way. The
/// selection shows the user's explicit pick, then the couch's pick, then the
/// file's default.
struct CouchTrackPickers: View {

    @InjectedObject(\.couchLanguageStore)
    private var couchLanguageStore: CouchLanguageStore

    @ObservedObject
    var provider: ItemContentGroupProvider

    init(provider: ItemContentGroupProvider) {
        self.provider = provider
    }

    // MARK: - Streams

    // TODO: Fix External Audio Tracks & Re-Enable
    @MainActor
    static func audioStreams(for provider: ItemContentGroupProvider) -> [MediaStream] {
        provider.mediaPlayerItemProvider?.mediaSource?.audioStreams?.filter { $0.isExternal != true } ?? []
    }

    @MainActor
    static func subtitleStreams(for provider: ItemContentGroupProvider) -> [MediaStream] {
        provider.mediaPlayerItemProvider?.mediaSource?.subtitleStreams ?? []
    }

    /// Whether there is an audio or subtitle track to pick.
    @MainActor
    static func hasTracks(for provider: ItemContentGroupProvider) -> Bool {
        audioStreams(for: provider).isNotEmpty || subtitleStreams(for: provider).isNotEmpty
    }

    private var audioStreams: [MediaStream] {
        Self.audioStreams(for: provider)
    }

    private var subtitleStreams: [MediaStream] {
        Self.subtitleStreams(for: provider)
    }

    // MARK: - Selection

    /// The couch's pick for the axes the user hasn't picked, so the pickers show what will play.
    /// `nil` for a solo couch, which keeps today's behaviour.
    private var couchDecision: CouchLanguageDecision? {
        _ = couchLanguageStore.revision

        guard let itemProvider = provider.mediaPlayerItemProvider,
              let mediaSource = itemProvider.mediaSource
        else { return nil }

        return CouchLanguages.decision(
            for: mediaSource,
            item: itemProvider.item,
            audioStreamIndex: itemProvider.audioStreamIndex,
            subtitleStreamIndex: itemProvider.subtitleStreamIndex
        )
    }

    private var audioStreamSelection: Binding<Int?> {
        Binding(
            get: {
                provider.mediaPlayerItemProvider?.audioStreamIndex
                    ?? couchDecision?.audioStreamIndex
                    ?? provider.mediaPlayerItemProvider?.mediaSource?.defaultAudioStreamIndex
                    ?? audioStreams.first?.index
            },
            set: { provider.select(.audioStreamIndex($0)) }
        )
    }

    private var subtitleStreamSelection: Binding<Int?> {
        Binding(
            get: {
                provider.mediaPlayerItemProvider?.subtitleStreamIndex
                    ?? couchDecision?.subtitleStreamIndex
                    ?? provider.mediaPlayerItemProvider?.mediaSource?.defaultSubtitleStreamIndex
                    ?? -1
            },
            set: { provider.select(.subtitleStreamIndex($0)) }
        )
    }

    // MARK: - Body

    @ViewBuilder
    private func trackPicker(
        _ title: String,
        streams: [MediaStream],
        selection: Binding<Int?>
    ) -> some View {
        Picker(selection: selection) {
            ForEach(streams, id: \.index) { stream in
                Text(stream.displayTitle ?? L10n.unknown)
                    .tag(stream.index as Int?)
            }
        } label: {
            Text(title)

            if let selectedStream = streams.first(where: { $0.index == selection.wrappedValue }) {
                Text(selectedStream.displayTitle ?? L10n.unknown)
            }
        }
        .pickerStyle(.menu)
    }

    var body: some View {
        if audioStreams.isNotEmpty {
            trackPicker(
                L10n.audio,
                streams: audioStreams,
                selection: audioStreamSelection
            )
        }

        if subtitleStreams.isNotEmpty {
            trackPicker(
                L10n.subtitles,
                streams: subtitleStreams.prepending(.none),
                selection: subtitleStreamSelection
            )
        }
    }
}
