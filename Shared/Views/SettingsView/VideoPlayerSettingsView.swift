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

struct VideoPlayerSettingsView: View {

    /// The video player settings are split over two screens in Settings.
    enum Page {
        /// Player, quality, autoplay, skip lengths and the player's controls.
        case playback
        /// Audio and subtitle languages, modes and the subtitle look.
        case audioAndSubtitles
    }

    #if os(tvOS)
    typealias PlatformPicker = ListRowMenu
    #else
    typealias PlatformPicker = Picker
    #endif

    // MARK: - Player Defaults

    @Default(.VideoPlayer.videoPlayerType)
    private var videoPlayerType

    // MARK: - Button Defaults

    @Default(.VideoPlayer.jumpBackwardInterval)
    private var jumpBackwardLength
    @Default(.VideoPlayer.jumpForwardInterval)
    private var jumpForwardLength
    @Default(.VideoPlayer.barActionButtons)
    private var barActionButtons
    @Default(.VideoPlayer.menuActionButtons)
    private var menuActionButtons

    // MARK: - Resume Defaults

    @Default(.VideoPlayer.resumeOffset)
    private var resumeOffset

    // MARK: - Slider Defaults

    @Default(.VideoPlayer.Overlay.chapterSlider)
    private var chapterSlider
    @StoredValue(.User.previewImageScrubbing)
    private var previewImageScrubbing: PreviewImageScrubbingOption

    // MARK: - Supplement Defaults

    @Default(.VideoPlayer.supplements)
    private var supplements

    // MARK: - Subtitle Defaults

    @Default(.VideoPlayer.Subtitle.configuration)
    private var subtitleConfiguration
    @StoredValue(.User.forceSubtitleBurnIn)
    private var forceSubtitleBurnIn

    // MARK: - Timestamp Defaults

    @Default(.VideoPlayer.Overlay.trailingTimestampType)
    private var trailingTimestampType

    @Router
    private var router

    @StateObject
    private var viewModel: ServerUserAdminViewModel

    let page: Page

    init(page: Page = .playback) {
        self.page = page
        _viewModel =
            StateObject(wrappedValue: ServerUserAdminViewModel(user: Container.shared.currentUserSession()?.user.data ?? UserDto()))
    }

    private func updateConfiguration(_ modify: (inout UserConfiguration) -> Void) {
        guard viewModel.user.id != nil else { return }
        guard var configuration = viewModel.user.configuration else { return }

        modify(&configuration)
        viewModel.updateConfiguration(configuration)
    }

    // MARK: - Body

    var body: some View {
        Form(systemImage: page == .playback ? "play.rectangle" : "captions.bubble") {
            switch page {
            case .playback:
                engineSettings

                whileWatchingSettings

                controlSettings

            case .audioAndSubtitles:
                audioSettings

                subtitleSettings
            }
        }
        .onFirstAppear {
            viewModel.refresh()
        }
        .toolbarTitleDisplayMode(.inline)
        .navigationTitle(
            page == .playback ? L10n.CouchfinSettings.playback : L10n.CouchfinSettings.audioAndSubtitles
        )
        .topBarTrailing {
            if viewModel.background.is(.updating) || viewModel.background.is(.refreshing) {
                ProgressView()
            }
        }
    }

    // MARK: - Engine Settings

    @ViewBuilder
    private var videoPlayerPicker: some View {
        Picker(L10n.player, selection: $videoPlayerType) {
            ForEach(VideoPlayerType.supportedCases, id: \.self) { player in
                Text(player.displayTitle).tag(player)
            }
        }
    }

    @ViewBuilder
    private var engineSettings: some View {
        Section(L10n.player) {
            #if os(iOS)
            videoPlayerPicker
            #else
            ListRowMenu(L10n.player, subtitle: videoPlayerType.displayTitle) {
                videoPlayerPicker
            }
            #endif

            ChevronButton(L10n.playbackQuality) {
                router.route(to: .playbackQualitySettings)
            }
        } learnMore: {
            LabeledContent(
                L10n.vlc,
                value: L10n.playerVlcDescription
            )
            LabeledContent(
                L10n.avPlayer,
                value: L10n.playerNativeDescription
            )
        }
    }

    // MARK: - Button Settings

    @ViewBuilder
    private func jumpIntervalPicker(title: String, selection: Binding<MediaJumpInterval>) -> some View {
        CustomAlertPicker(
            title: title,
            selection: selection,
            customTitle: L10n.jump,
            customDescription: L10n.customJumpIntervalDescription
        ) { value in
            TextField(
                L10n.duration,
                value: value
                    .map(
                        getter: { Int($0.rawValue.seconds) },
                        setter: { MediaJumpInterval(rawValue: .seconds($0)) }
                    )
                    .clamp(min: 1, max: 600),
                format: .number
            )
            .keyboardType(.numberPad)
        }
    }

    // MARK: - While Watching Settings

    @ViewBuilder
    private var whileWatchingSettings: some View {
        Section {
            Toggle(L10n.autoPlay, isOn: Binding(
                get: { viewModel.user.configuration?.enableNextEpisodeAutoPlay == true },
                set: { newValue in
                    updateConfiguration { $0.enableNextEpisodeAutoPlay = newValue }
                }
            ))

            jumpIntervalPicker(
                title: L10n.jumpBackwardLength,
                selection: $jumpBackwardLength
            )

            jumpIntervalPicker(
                title: L10n.jumpForwardLength,
                selection: $jumpForwardLength
            )

            Stepper(L10n.resumeOffset, value: $resumeOffset, in: 0 ... 30, step: 1) {
                LabeledContent(L10n.resumeOffset) {
                    Text(resumeOffset, format: SecondFormatter())
                        .foregroundStyle(.secondary)
                }
            }

            PlatformPicker(L10n.trailingValue, selection: $trailingTimestampType)
        } header: {
            Text(L10n.CouchfinSettings.whileWatching)
        } footer: {
            Text(L10n.resumeOffsetDescription)
        }
    }

    // MARK: - Control Settings

    @ViewBuilder
    private var controlSettings: some View {
        Section(L10n.CouchfinSettings.controls) {
            ChevronButton(L10n.barButtons) {
                router.route(to: .actionBarButtonSelector(
                    selectedButtonsBinding: $barActionButtons
                ))
            }

            ChevronButton(L10n.menuButtons) {
                router.route(to: .actionMenuButtonSelector(
                    selectedButtonsBinding: $menuActionButtons
                ))
            }

            #if os(iOS)
            ChevronButton(L10n.gestures) {
                router.route(to: .gestureSettings)
            }
            #endif

            ChevronButton(L10n.supplements) {
                router.route(to: .supplementSelector(
                    selectedSupplementsBinding: $supplements
                ))
            }

            Toggle(L10n.chapterSlider, isOn: $chapterSlider)

            PlatformPicker(L10n.previewImage, selection: $previewImageScrubbing)
        }
        .onChange(of: barActionButtons) {
            let enabled = barActionButtons.contains(.autoPlay) || menuActionButtons.contains(.autoPlay)
            updateConfiguration { $0.enableNextEpisodeAutoPlay = enabled }
        }
        .onChange(of: menuActionButtons) {
            let enabled = menuActionButtons.contains(.autoPlay) || barActionButtons.contains(.autoPlay)
            updateConfiguration { $0.enableNextEpisodeAutoPlay = enabled }
        }
    }

    // MARK: - Audio Settings

    @ViewBuilder
    private var audioSettings: some View {
        Section(L10n.audio) {
            CulturePicker(L10n.preferredLanguage, threeLetterISOLanguageName: Binding(
                get: { viewModel.user.configuration?.audioLanguagePreference },
                set: { newValue in
                    updateConfiguration { $0.audioLanguagePreference = newValue }
                }
            ))

            Toggle(L10n.playDefaultTrack, isOn: Binding(
                get: { viewModel.user.configuration?.isPlayDefaultAudioTrack == true },
                set: { newValue in
                    updateConfiguration { $0.isPlayDefaultAudioTrack = newValue }
                }
            ))

            Toggle(L10n.rememberTrackSelection, isOn: Binding(
                get: { viewModel.user.configuration?.isRememberAudioSelections == true },
                set: { newValue in
                    updateConfiguration { $0.isRememberAudioSelections = newValue }
                }
            ))
        } learnMore: {
            LabeledContent(
                L10n.playDefault,
                value: L10n.playDefaultTrackDescription
            )

            LabeledContent(
                L10n.rememberTrackSelection,
                value: L10n.rememberTrackSelectionDescription
            )
        }
    }

    // MARK: - Subtitle Settings

    @ViewBuilder
    private var subtitleSettings: some View {
        Section(L10n.subtitles) {
            CulturePicker(L10n.preferredLanguage, threeLetterISOLanguageName: Binding(
                get: { viewModel.user.configuration?.subtitleLanguagePreference },
                set: { newValue in
                    updateConfiguration { $0.subtitleLanguagePreference = newValue }
                }
            ))

            PlatformPicker(L10n.subtitleMode, selection: Binding(
                get: { viewModel.user.configuration?.subtitleMode ?? .default },
                set: { newValue in
                    updateConfiguration { $0.subtitleMode = newValue }
                }
            ))

            Toggle(L10n.rememberTrackSelection, isOn: Binding(
                get: { viewModel.user.configuration?.isRememberSubtitleSelections == true },
                set: { newValue in
                    updateConfiguration { $0.isRememberSubtitleSelections = newValue }
                }
            ))

            Toggle(
                L10n.forceSubtitleBurnIn,
                isOn: $forceSubtitleBurnIn
            )
        } footer: {
            Text(L10n.forceSubtitleBurnInMessage)
        } learnMore: {
            LabeledContent(
                SubtitlePlaybackMode.default.displayTitle,
                value: SubtitlePlaybackMode.default.description
            )

            LabeledContent(
                SubtitlePlaybackMode.always.displayTitle,
                value: SubtitlePlaybackMode.always.description
            )

            LabeledContent(
                SubtitlePlaybackMode.onlyForced.displayTitle,
                value: SubtitlePlaybackMode.onlyForced.description
            )

            LabeledContent(
                SubtitlePlaybackMode.none.displayTitle,
                value: SubtitlePlaybackMode.none.description
            )

            LabeledContent(
                SubtitlePlaybackMode.smart.displayTitle,
                value: SubtitlePlaybackMode.smart.description
            )
        }

        Section {
            ChevronButton(L10n.subtitleFont, content: subtitleConfiguration.fontName) {
                router.route(to: .fontPicker(selection: $subtitleConfiguration.fontName))
            }

            Stepper(L10n.subtitleSize, value: $subtitleConfiguration.size, in: 1 ... 20, step: 1) {
                LabeledContent(L10n.subtitleSize) {
                    Text(subtitleConfiguration.size.description)
                        .foregroundStyle(.secondary)
                }
            }

            ColorPicker(L10n.subtitleColor, selection: $subtitleConfiguration.color, supportsOpacity: false)
        } footer: {
            // TODO: better wording
            Text(L10n.subtitlesDisclaimer)
        }
    }
}
