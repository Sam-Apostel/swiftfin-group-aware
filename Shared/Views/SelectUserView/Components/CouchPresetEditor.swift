//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

/// What the "Save this couch" / "Edit couch" prompt is editing.
struct CouchPresetDraft: Identifiable {

    let id = UUID()
    /// `nil` for a new preset.
    let presetID: String?
    let serverID: String
    let memberIDs: [String]
    let memberNames: [String]
    var name: String
    var emoji: String
}

extension View {

    /// Presents a name + emoji prompt for `draft` while it is non-nil.
    func couchPresetEditor(
        draft: Binding<CouchPresetDraft?>,
        onCommit: @escaping (CouchPresetDraft) -> Void
    ) -> some View {
        modifier(CouchPresetEditorModifier(draft: draft, onCommit: onCommit))
    }
}

struct CouchPresetEditorModifier: ViewModifier {

    @Binding
    var draft: CouchPresetDraft?

    let onCommit: (CouchPresetDraft) -> Void

    private var isPresented: Binding<Bool> {
        Binding(
            get: { draft != nil },
            set: { isPresented in
                if !isPresented {
                    draft = nil
                }
            }
        )
    }

    private var name: Binding<String> {
        Binding(
            get: { draft?.name ?? "" },
            set: { draft?.name = $0 }
        )
    }

    private var emoji: Binding<String> {
        Binding(
            get: { draft?.emoji ?? "" },
            set: { draft?.emoji = $0 }
        )
    }

    private var title: String {
        draft?.presetID == nil ? L10n.CouchPresets.saveCouchTitle : L10n.CouchPresets.editCouchTitle
    }

    private var canSave: Bool {
        CouchPreset.sanitizedName(draft?.name ?? "").isNotEmpty
    }

    func body(content: Content) -> some View {
        content
            .alert(title, isPresented: isPresented) {
                TextField(L10n.CouchPresets.namePlaceholder, text: name)

                TextField(L10n.CouchPresets.emojiPlaceholder, text: emoji)

                Button(L10n.cancel, role: .cancel) {
                    draft = nil
                }

                Button(L10n.save) {
                    if let draft {
                        onCommit(draft)
                    }
                    draft = nil
                }
                .disabled(!canSave)
            } message: {
                if let draft {
                    Text(L10n.CouchPresets.members(draft.memberNames))
                }
            }
    }
}
