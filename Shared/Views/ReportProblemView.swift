//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

/// "Report a problem": a bug or an idea, with non-sensitive diagnostics attached, sent to the
/// T-Minus inbox. From the player it also describes what's playing.
struct ReportProblemView: View {

    private enum Field: Hashable {
        case title
        case details
    }

    private enum Outcome {
        case sent
        case saved
        case failed

        var title: String {
            switch self {
            case .sent: L10n.ReportProblem.sentTitle
            case .saved: L10n.ReportProblem.savedTitle
            case .failed: L10n.ReportProblem.failedTitle
            }
        }

        var message: String {
            switch self {
            case .sent: L10n.ReportProblem.sentMessage
            case .saved: L10n.ReportProblem.savedMessage
            case .failed: L10n.ReportProblem.failedMessage
            }
        }
    }

    @Default(.accentColor)
    private var accentColor

    @FocusState
    private var focusedField: Field?

    @Router
    private var router

    @State
    private var details: String = ""
    @State
    private var diagnostics: [ProblemReportDiagnostics.Line] = []
    @State
    private var isSending: Bool = false
    @State
    private var kind: TMinusClient.FeedbackKind = .bug
    @State
    private var outcome: Outcome?
    @State
    private var title: String = ""

    private let isPresentedAsSheet: Bool
    private let playback: PlaybackReportContext?

    init(playback: PlaybackReportContext? = nil, isPresentedAsSheet: Bool = false) {
        self.playback = playback
        self.isPresentedAsSheet = isPresentedAsSheet
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSendDisabled: Bool {
        isSending || trimmedTitle.isEmpty
    }

    // MARK: - Body

    var body: some View {
        Form(systemImage: "exclamationmark.bubble.fill") {
            kindSection

            messageSection

            sendSection

            diagnosticsSection
        }
        .navigationTitle(L10n.ReportProblem.title)
        .navigationBarTitleDisplayMode(.inline)
        .if(isPresentedAsSheet) { view in
            view
                .navigationBarCloseButton {
                    router.dismiss()
                }
        }
        .onFirstAppear {
            diagnostics = ProblemReportDiagnostics.lines(playback: playback)
            focusedField = .title
        }
        .alert(
            outcome?.title ?? "",
            isPresented: Binding(
                get: { outcome != nil },
                set: { isPresented in
                    if !isPresented {
                        outcome = nil
                    }
                }
            ),
            presenting: outcome
        ) { presented in
            Button(L10n.ok) {
                outcome = nil

                if presented != .failed {
                    router.dismiss()
                }
            }
        } message: { presented in
            Text(presented.message)
        }
    }

    // MARK: - Actions

    private func send() {
        guard !isSendDisabled else { return }

        focusedField = nil
        isSending = true

        let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = [trimmedDetails, ProblemReportDiagnostics.text(diagnostics)]
            .filter(\.isNotEmpty)
            .joined(separator: "\n\n")
        let feedback = TMinusClient.Feedback(kind: kind, title: trimmedTitle, body: body)

        Task { @MainActor in
            do {
                switch try await TMinusClient.sendFeedback(feedback) {
                case .sent:
                    outcome = .sent
                case .saved:
                    outcome = .saved
                }
                UIDevice.feedback(.success)
            } catch {
                outcome = .failed
                UIDevice.feedback(.error)
            }
            isSending = false
        }
    }

    // MARK: - Kind Section

    private var kindSection: some View {
        Section {
            Picker(L10n.ReportProblem.kind, selection: $kind) {
                Text(L10n.ReportProblem.broken)
                    .tag(TMinusClient.FeedbackKind.bug)
                Text(L10n.ReportProblem.idea)
                    .tag(TMinusClient.FeedbackKind.feature)
            }
            .disabled(isSending)
        }
    }

    // MARK: - Message Section

    private var messageSection: some View {
        Section {
            TextField(
                L10n.ReportProblem.summary,
                text: $title,
                prompt: Text(kind == .bug ? L10n.ReportProblem.brokenPrompt : L10n.ReportProblem.ideaPrompt)
            )
            #if os(iOS)
            .submitLabel(.next)
            #endif
            .focused($focusedField, equals: .title)
            .onSubmit {
                focusedField = .details
            }
            .disabled(isSending)

            TextField(
                L10n.ReportProblem.details,
                text: $details,
                prompt: Text(L10n.ReportProblem.detailsPrompt),
                axis: .vertical
            )
            #if os(iOS)
            .lineLimit(3 ... 10)
            #endif
            .focused($focusedField, equals: .details)
            .disabled(isSending)
        }
    }

    // MARK: - Send Section

    private var sendSection: some View {
        Section {
            Button {
                send()
            } label: {
                ZStack {
                    if isSending {
                        ProgressView()
                    } else {
                        Text(L10n.ReportProblem.send)
                    }
                }
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
            .disabled(isSendDisabled)
        }
    }

    // MARK: - Diagnostics Section

    private var diagnosticsSection: some View {
        Section {
            ForEach(diagnostics) { line in
                LabeledContent(line.label, value: line.value)
                    .font(.footnote)
            }
        } header: {
            Text(L10n.ReportProblem.sentAlong)
        } footer: {
            Text(L10n.ReportProblem.sentAlongFooter)
        }
    }
}
