//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import SwiftUI

/// "Add to my iPhone calendar", in "Coming up" and in Settings.
struct ReleaseCalendarSyncToggle: View {

    @InjectedObject(\.releaseCalendarSync)
    private var calendarSync: ReleaseCalendarSync

    @State
    private var error: Error?

    private var isOn: Binding<Bool> {
        Binding(
            get: { calendarSync.isEnabled },
            set: { setEnabled($0) }
        )
    }

    private func setEnabled(_ isEnabled: Bool) {
        Task {
            do {
                try await calendarSync.setEnabled(isEnabled)
            } catch {
                self.error = error
            }
        }
    }

    var body: some View {
        Toggle(isOn: isOn) {
            Label(L10n.ReleaseCalendar.addToCalendar, systemImage: "calendar.badge.plus")
        }
        .disabled(calendarSync.isSyncing)
        .errorMessage($error)
    }
}
