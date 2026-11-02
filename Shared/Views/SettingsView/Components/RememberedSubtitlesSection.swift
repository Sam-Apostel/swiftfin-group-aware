//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import FactoryKit
import SwiftUI

/// Shows the subtitle choice remembered for the signed-in user, with a way to forget it.
struct RememberedSubtitlesSection: View {

    @Default(.subtitlePreferences)
    private var subtitlePreferences

    /// Called after the remembered choice is dropped from this device, to reset the server's subtitle mode.
    private let onForget: () -> Void

    init(onForget: @escaping () -> Void) {
        self.onForget = onForget
    }

    private var userID: String? {
        Container.shared.currentUserSession()?.user.id
    }

    private var preference: SubtitlePreference? {
        guard let userID else { return nil }

        return subtitlePreferences[userID]
    }

    var body: some View {
        Section {
            if let preference {
                LabeledContent(
                    L10n.RememberedSubtitles.title,
                    value: L10n.RememberedSubtitles.remembered(preference.summary)
                )

                Button(L10n.RememberedSubtitles.forget, role: .destructive) {
                    SubtitlePreferenceStore.clearLocalPreference(for: userID)
                    onForget()
                }
            } else {
                LabeledContent(
                    L10n.RememberedSubtitles.title,
                    value: L10n.RememberedSubtitles.notYet
                )
            }
        } footer: {
            Text(L10n.RememberedSubtitles.footer)
        }
    }
}

extension SubtitlePreference {

    /// "Off", "English" or "English (SDH)".
    var summary: String {
        guard isEnabled else { return L10n.RememberedSubtitles.off }

        let languageName = language.map { code in
            Locale.current.localizedString(forLanguageCode: code) ?? code.uppercased()
        } ?? L10n.RememberedSubtitles.unknownLanguage

        switch flavour {
        case .regular:
            return languageName
        case .forced:
            let flavourName = L10n.RememberedSubtitles.forced
            return L10n.RememberedSubtitles.languageWithFlavour(languageName, flavourName)

        case .hearingImpaired:
            let flavourName = L10n.RememberedSubtitles.sdh
            return L10n.RememberedSubtitles.languageWithFlavour(languageName, flavourName)
        }
    }
}
