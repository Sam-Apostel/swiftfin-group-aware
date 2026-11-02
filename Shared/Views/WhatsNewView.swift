//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

/// The release notes bundled with this build (see `BundledReleaseNotes`): from Settings, and once
/// as a sheet after an update.
struct WhatsNewView: View {

    @Default(.accentColor)
    private var accentColor

    @Environment(\.dismiss)
    private var dismiss

    private let notes: BundledReleaseNotes?
    private let isPresentedAsSheet: Bool

    init(notes: BundledReleaseNotes? = BundledReleaseNotes.current, isPresentedAsSheet: Bool = false) {
        self.notes = notes
        self.isPresentedAsSheet = isPresentedAsSheet
    }

    // MARK: - Body

    var body: some View {
        Group {
            if let notes, !notes.isEmpty {
                notesForm(notes)
            } else {
                FinEmptyView(
                    L10n.WhatsNew.emptyTitle,
                    description: L10n.WhatsNew.emptyDescription
                )
            }
        }
        .navigationTitle(isPresentedAsSheet ? L10n.WhatsNew.thisVersion : L10n.WhatsNew.title)
        .navigationBarTitleDisplayMode(.inline)
        .if(isPresentedAsSheet) { view in
            view
                .navigationBarCloseButton {
                    dismiss()
                }
        }
    }

    private func notesForm(_ notes: BundledReleaseNotes) -> some View {
        Form(systemImage: "sparkles") {
            if let version = notes.versionLabel {
                Section {
                    Text(L10n.WhatsNew.version(version))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            noteSection(L10n.WhatsNew.new, notes: notes.newNotes, systemImage: "sparkle")

            noteSection(L10n.WhatsNew.pleaseTry, notes: notes.notesToTry, systemImage: "hand.tap")

            if isPresentedAsSheet {
                Section {
                    Button {
                        dismiss()
                    } label: {
                        Text(L10n.WhatsNew.gotIt)
                            .frame(maxWidth: .infinity)
                    }
                    .listRowInsets(.zero)
                    .listRowBackground(Color.clear)
                    .fontWeight(.semibold)
                    .backport
                    .buttonStyle(.glassProminent.shadow(false))
                    .tint(accentColor)
                    #if os(iOS)
                    .controlSize(.large)
                    .listRowSeparator(.hidden)
                    #endif
                    .frame(maxHeight: 75)
                }
            }
        }
    }

    @ViewBuilder
    private func noteSection(_ title: String, notes: [BundledReleaseNotes.Note], systemImage: String) -> some View {
        if notes.isNotEmpty {
            Section(title) {
                ForEach(notes, id: \.self) { note in
                    Label {
                        Text(note.text)
                    } icon: {
                        Image(systemName: systemImage)
                            .foregroundStyle(accentColor)
                    }
                    #if os(tvOS)
                    // Focusable, so long notes can be scrolled to with the Siri Remote
                    .focusable()
                    #endif
                }
            }
        }
    }
}

extension View {

    /// Shows this build's release notes once, after an update. Does nothing when the build has no notes.
    func whatsNewAfterUpdate() -> some View {
        modifier(WhatsNewAfterUpdateModifier())
    }
}

private struct WhatsNewAfterUpdateModifier: ViewModifier {

    @State
    private var isPresented: Bool = false
    @State
    private var notes: BundledReleaseNotes?

    func body(content: Content) -> some View {
        content
            .task {
                // Let the home screen settle first.
                try? await Task.sleep(for: .seconds(1))

                guard let unseen = BundledReleaseNotes.unseen else { return }

                BundledReleaseNotes.markShown()
                notes = unseen
                isPresented = true
            }
            .sheet(isPresented: $isPresented) {
                NavigationStack {
                    WhatsNewView(notes: notes, isPresentedAsSheet: true)
                }
            }
    }
}
