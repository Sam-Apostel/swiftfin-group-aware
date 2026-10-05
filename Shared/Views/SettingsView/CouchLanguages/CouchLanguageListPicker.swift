//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import JellyfinAPI
import SwiftUI

/// A multi-select list of languages, from the server's cultures (the same source as `CulturePicker`).
///
/// The selection holds canonical codes (`CouchLanguageCode.canonical`). Sections: the selected languages,
/// a few common ones, then every language sorted by name. No search field, to avoid tvOS quirks.
struct CouchLanguageListPicker: View {

    private struct Language: Hashable, Identifiable {
        let code: String
        let name: String

        var id: String {
            code
        }
    }

    /// Dutch, English, French, German, Spanish.
    private static let commonCodes = ["dut", "eng", "fre", "ger", "spa"]

    @Default(.accentColor)
    private var accentColor

    /// Mirrors the binding, so this view updates even when presented away from the binding's owner.
    @StateObject
    private var box: PublishedBox<[String]>
    @StateObject
    private var viewModel: PagingLibraryViewModel<CultureLibrary>

    private let title: String

    init(title: String, selection: Binding<[String]>) {
        self.title = title
        self._box = StateObject(wrappedValue: PublishedBox(source: selection))
        self._viewModel = StateObject(wrappedValue: PagingLibraryViewModel(library: CultureLibrary()))
    }

    // MARK: - Body

    var body: some View {
        let languages = allLanguages

        List {
            selectedSection(languages)

            commonSection(languages)

            allLanguagesSection(languages)
        }
        .focusSection()
        .navigationTitle(title)
        .onFirstAppear {
            viewModel.refresh()
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func selectedSection(_ languages: [Language]) -> some View {
        if box.value.isNotEmpty {
            Section {
                ForEach(box.value, id: \.self) { code in
                    row(Language(code: code, name: name(for: code, in: languages)))
                }
            } header: {
                Text(L10n.CouchLanguageSettings.selected)
            }
        }
    }

    @ViewBuilder
    private func commonSection(_ languages: [Language]) -> some View {
        Section {
            ForEach(Self.commonCodes, id: \.self) { code in
                row(Language(code: code, name: name(for: code, in: languages)))
            }
        } header: {
            Text(L10n.CouchLanguageSettings.common)
        }
    }

    @ViewBuilder
    private func allLanguagesSection(_ languages: [Language]) -> some View {
        Section {
            if viewModel.state == .initial || viewModel.state == .refreshing {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if languages.isEmpty {
                unavailableView
            } else {
                ForEach(languages) { language in
                    row(language)
                }
            }
        } header: {
            Text(L10n.CouchLanguageSettings.allLanguages)
        }
    }

    @ViewBuilder
    private var unavailableView: some View {
        ContentUnavailableView {
            Label(L10n.CouchLanguageSettings.languagesUnavailable, systemImage: "character.bubble")
        } description: {
            Text(L10n.CouchLanguageSettings.languagesUnavailableDescription)
        } actions: {
            Button(L10n.retry) {
                viewModel.refresh()
            }
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func row(_ language: Language) -> some View {
        let isSelected = box.value.contains(language.code)

        Button {
            toggle(language.code)
        } label: {
            HStack {
                Text(language.name)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isSelected {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(accentColor)
                }
            }
        }
        .foregroundStyle(.primary, .secondary)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Helpers

    /// Every culture with a known language, one per canonical code, sorted by name.
    private var allLanguages: [Language] {
        var seen: Set<String> = []
        var languages: [Language] = []

        for culture in viewModel.elements {
            guard let code = CouchLanguageCode.canonical(culture.threeLetterISOLanguageName),
                  seen.insert(code).inserted
            else { continue }

            languages.append(Language(code: code, name: culture.displayTitle))
        }

        return languages.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The culture's name when loaded, else the system's name for the code (works offline).
    private func name(for code: String, in languages: [Language]) -> String {
        languages.first { $0.code == code }?.name ?? CouchLanguages.displayName(forLanguage: code)
    }

    private func toggle(_ code: String) {
        if let index = box.value.firstIndex(of: code) {
            box.value.remove(at: index)
        } else {
            box.value.append(code)
        }
    }
}
