//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import SwiftUI
import UIKit

extension NavigationRoute {

    static var lighterCopies: NavigationRoute {
        NavigationRoute(
            id: "lighterCopies"
        ) {
            LighterCopiesView()
        }
    }
}

/// The "Needs a lighter copy" list: items that stuttered for any user on this server,
/// with why and what copy would play smoothly.
struct LighterCopiesView: View {

    @State
    private var entries: [LighterCopyEntry] = []
    @State
    private var error: Error?
    @State
    private var isLoading = true

    private var listText: String {
        entries
            .map { L10n.PlaybackHealth.listLine(name: $0.name, reason: $0.reason, target: $0.target) }
            .joined(separator: "\n\n")
    }

    var body: some View {
        List {
            ListTitleSection(
                L10n.PlaybackHealth.lighterCopies,
                description: L10n.PlaybackHealth.lighterCopiesDescription
            )

            if isLoading, entries.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if entries.isEmpty {
                Text(L10n.PlaybackHealth.noLighterCopies)
                    .foregroundStyle(.secondary)
            } else {
                Section {
                    ForEach(entries) { entry in
                        row(entry)
                            .swipeActions {
                                Button(L10n.PlaybackHealth.markDone, role: .destructive) {
                                    remove(entry)
                                }
                            }
                    }
                }
            }
        }
        .navigationTitle(L10n.PlaybackHealth.lighterCopies)
        .toolbarTitleDisplayMode(.inline)
        .refreshable {
            await load()
        }
        .task {
            await load()
        }
        .topBarTrailing {
            if entries.isNotEmpty {
                Button(L10n.PlaybackHealth.copyList, systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = listText
                    UIDevice.feedback(.success)
                }
            }
        }
        .errorMessage($error)
    }

    private func row(_ entry: LighterCopyEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.name)
                .font(.headline)

            Text(entry.reason)
                .font(.subheadline)

            if entry.target.isNotEmpty {
                Text(entry.target)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text(L10n.PlaybackHealth.stallsTotal(entry.stalls))
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(
                L10n.PlaybackHealth.reportedBy(
                    entry.reportedBy,
                    device: entry.device,
                    date: entry.updatedAt.formatted(date: .abbreviated, time: .omitted)
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func load() async {
        guard let userSession = Container.shared.currentUserSession() else { return }

        isLoading = true

        do {
            entries = try await LighterCopyStore.allEntries(userSession: userSession)
        } catch {
            self.error = error
        }

        isLoading = false
    }

    private func remove(_ entry: LighterCopyEntry) {
        guard let userSession = Container.shared.currentUserSession() else { return }

        entries.removeAll { $0.id == entry.id }

        Task {
            do {
                try await LighterCopyStore.remove(itemID: entry.id, userSession: userSession)
            } catch {
                self.error = error
                await load()
            }
        }
    }
}
