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

/// The couch line under the action buttons in `ItemView.ActionBar`, for a group couch:
///
///     🛋 Watching as Sam, Lisa and Tuur
///        Dutch audio · no subtitles — Tuur is on the couch ⌃⌄
///
/// The second line is the couch's language pick for the item that Play would start.
/// It uses the same inputs as `MediaPlayerItem.build`, including the user's explicit
/// track picks, so it always matches what will play. When there is a pick, the line
/// is a `Menu` with the audio and subtitle pickers (`CouchTrackPickers`), two presses
/// down from Play on Apple TV. Without one, it is a single plain line that never
/// takes focus.
///
/// It also presents the "Mark unwatched for…" dialog of `ItemActionButtons.Played`,
/// so that dialog works when the button sits in a menu.
///
/// A solo couch shows nothing new.
struct CouchLanguageLabel: View {

    @Injected(\.currentUserSession)
    private var userSession: UserSession?

    @InjectedObject(\.couchLanguageStore)
    private var store: CouchLanguageStore

    @ObservedObject
    var provider: ItemContentGroupProvider

    init(provider: ItemContentGroupProvider) {
        self.provider = provider
    }

    private var decision: CouchLanguageDecision? {
        // Read `revision` so edits made in Couch settings re-render the label.
        _ = store.revision

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

    /// The track line of a group couch: the couch's pick, or the user's own picks once
    /// the couch has nothing left to decide, so the menu stays where the user just used it.
    private var trackSummary: String? {
        if let decision {
            return decision.summary
        }

        guard let itemProvider = provider.mediaPlayerItemProvider,
              itemProvider.audioStreamIndex != nil || itemProvider.subtitleStreamIndex != nil,
              CouchTrackPickers.hasTracks(for: provider)
        else { return nil }

        return pickedSummary(itemProvider)
    }

    /// "Dutch audio · no subtitles" for the user's explicit picks.
    private func pickedSummary(_ itemProvider: MediaPlayerItemProvider) -> String {
        let audioIndex = itemProvider.audioStreamIndex ?? itemProvider.mediaSource?.defaultAudioStreamIndex
        let audioStream = CouchTrackPickers.audioStreams(for: provider)
            .first { $0.index == audioIndex }

        let audio = if let language = audioStream?.language {
            L10n.CouchLanguages.audio(CouchLanguages.displayName(forLanguage: language))
        } else {
            L10n.CouchLanguages.chosenAudio
        }

        let subtitleIndex = itemProvider.subtitleStreamIndex ?? itemProvider.mediaSource?.defaultSubtitleStreamIndex ?? -1
        let subtitleStream = CouchTrackPickers.subtitleStreams(for: provider)
            .first { $0.index == subtitleIndex }

        let subtitles = if subtitleIndex < 0 || subtitleStream == nil {
            L10n.CouchLanguages.noSubtitles
        } else if let language = subtitleStream?.language {
            L10n.CouchLanguages.subtitles(CouchLanguages.displayName(forLanguage: language))
        } else {
            L10n.CouchLanguages.chosenSubtitles
        }

        return L10n.CouchLanguages.summary(audio: audio, subtitles: subtitles)
    }

    private var font: Font {
        UIDevice.isTV ? .caption : .callout
    }

    // MARK: - Body

    var body: some View {
        if let userSession, userSession.couch.isGroup {
            groupLine(couch: userSession.couch)
                .font(font)
                .lineLimit(2)
                .transition(.opacity)
                .task(id: userSession.couch.id) {
                    await refreshProfiles()
                }
                .confirmationDialog(
                    L10n.CouchItem.markUnwatchedFor,
                    isPresented: $provider.isPresentingUnplayedChoice,
                    titleVisibility: .visible
                ) {
                    unplayedChoices(primaryName: userSession.user.username)
                }
        } else if let summary = decision?.summary {
            // Solo: unchanged (the couch doesn't decide languages for one person).
            Label {
                Text(summary)
            } icon: {
                Image(systemName: "sofa.fill")
            }
            .font(font)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .accessibilityElement(children: .combine)
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private func groupLine(couch: CouchGroup) -> some View {
        if let trackSummary {
            Menu {
                CouchTrackPickers(provider: provider)
            } label: {
                trackMenuLabel(couch: couch, summary: trackSummary)
            }
            .buttonStyle(BasicHoverButtonStyle())
            .if(UIDevice.isTV) { menu in
                menu.menuStyle(.button)
            }
            .accessibilityHint(L10n.CouchItem.changeTracksHint)
        } else {
            watchingAsLabel(couch: couch)
                .accessibilityElement(children: .combine)
        }
    }

    /// "🛋 Watching as Sam, Lisa and Tuur", plain and never focusable.
    @ViewBuilder
    private func watchingAsLabel(couch: CouchGroup) -> some View {
        Label {
            Text(L10n.Couch.watchingAs(couch.displayNames))
        } icon: {
            Image(systemName: "sofa.fill")
        }
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func trackMenuLabel(couch: CouchGroup, summary: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.Couch.watchingAs(couch.displayNames))
                    .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    Text(summary)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .accessibilityHidden(true)
                }
            }
            .multilineTextAlignment(.leading)
        } icon: {
            Image(systemName: "sofa.fill")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func unplayedChoices(primaryName: String) -> some View {
        Button(L10n.CouchItem.everyoneOnTheCouch, role: .destructive) {
            Task {
                await provider.setIsPlayedOnCouch(false, forEveryone: true)
            }
        }

        Button(L10n.CouchItem.just(primaryName)) {
            Task {
                await provider.setIsPlayedOnCouch(false, forEveryone: false)
            }
        }

        Button(L10n.cancel, role: .cancel) {}
    }

    /// Refreshes every member's language profile in the background (throttled in the store),
    /// so the playback hook reads fresh preferences when Play is pressed.
    private func refreshProfiles() async {
        guard let userSession, userSession.couch.isGroup else { return }

        await store.refreshIfNeeded(couch: userSession.couch, in: userSession)
    }
}
