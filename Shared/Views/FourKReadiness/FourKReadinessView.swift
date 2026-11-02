//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

#if os(tvOS)
extension NavigationRoute {

    static var fourKReadiness: NavigationRoute {
        NavigationRoute(
            id: "fourKReadiness"
        ) {
            FourKReadinessView()
        }
    }
}
#endif

/// "What it takes to watch 4K on this TV": checks the TV, the network, the player, the library and the server,
/// and says in plain words what to fix.
struct FourKReadinessView: View {

    @StateObject
    private var probe = FourKReadinessProbe()

    var body: some View {
        Form(systemImage: "4k.tv") {
            Section {
                summary

                Button(L10n.FourKReadiness.checkAgain) {
                    probe.check()
                }
                .disabled(probe.isChecking)
            }

            if let report = probe.report {
                Section {
                    ForEach(report.rows) { row in
                        FourKReadinessRowView(row: row)
                    }
                } footer: {
                    if report.totalCount > report.scannedCount {
                        Text(L10n.FourKReadiness.scanLimited(scanned: report.scannedCount, total: report.totalCount))
                    }
                }
            }
        }
        .navigationTitle(L10n.FourKReadiness.title)
        .onFirstAppear {
            probe.check()
        }
    }

    private var summary: some View {
        HStack(spacing: 16) {
            if probe.isChecking || probe.report == nil {
                ProgressView()

                Text(L10n.FourKReadiness.checking)
                    .foregroundStyle(.secondary)
            } else if let report = probe.report {
                Image(systemName: report.fixCount == 0 ? "checkmark.seal.fill" : "wrench.and.screwdriver.fill")
                    .foregroundStyle(report.fixCount == 0 ? Color.green : Color.orange)

                Text(report.fixCount == 0 ? L10n.FourKReadiness.overallReady : L10n.FourKReadiness.overallFixes(report.fixCount))
                    .font(.headline)
            }
        }
        .padding(.vertical, 8)
    }
}

/// One checklist row: ✓ or fix-this, what was found, and what to do.
private struct FourKReadinessRowView: View {

    let row: FourKReadinessRow

    private var systemImage: String {
        switch row.status {
        case .ready:
            "checkmark.circle.fill"
        case .fix:
            "exclamationmark.circle.fill"
        case .note:
            "info.circle.fill"
        }
    }

    private var color: Color {
        switch row.status {
        case .ready:
            .green
        case .fix:
            .orange
        case .note:
            .secondary
        }
    }

    var body: some View {
        // A button so the row takes focus and the list scrolls with the remote.
        Button {} label: {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Image(systemName: systemImage)
                    .foregroundStyle(color)

                VStack(alignment: .leading, spacing: 6) {
                    Text(row.title)
                        .font(.headline)

                    Text(row.detail)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let fix = row.fix {
                        Text(fix)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
        }
    }
}
