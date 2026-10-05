//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if os(iOS)
import Defaults
import JellyfinAPI
import SwiftUI

/// The iOS "It's ready" banner: a material card at the top of the screen, inside the safe area.
///
/// Tap it to open the title, swipe it up or press × to dismiss it.
/// VoiceOver reads it as one button with the message.
struct ReadyAlertsBannerCard: View {

    @Default(.accentColor)
    private var accentColor

    @State
    private var dragOffset: CGFloat = 0

    private let message: String
    private let item: BaseItemDto?
    private let onOpen: () -> Void
    private let onDismiss: () -> Void

    init(
        message: String,
        item: BaseItemDto?,
        onOpen: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.message = message
        self.item = item
        self.onOpen = onOpen
        self.onDismiss = onDismiss
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
    }

    // MARK: - Poster

    @ViewBuilder
    private var poster: some View {
        if let item {
            PosterImage(
                item: item,
                type: .portrait,
                size: .small
            )
            .frame(width: 44, height: 66)
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.complexSecondary)
                .frame(width: 44, height: 66)
                .overlay {
                    Image(systemName: "sparkles")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
        }
    }

    // MARK: - Text

    private var text: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L10n.ReadyAlerts.itsReady)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(accentColor)

            Text(message)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Buttons

    private var openButton: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                poster

                text
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(message))
        .accessibilityHint(Text(L10n.ReadyAlertsBanner.openHint))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text(L10n.dismiss)) {
            onDismiss()
        }
    }

    private var closeButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(.thinMaterial, in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(L10n.close))
    }

    // MARK: - Swipe up to dismiss

    private var swipeToDismiss: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                let height = value.translation.height
                // Follow the finger upwards, resist downwards.
                dragOffset = height < 0 ? height : height / 4
            }
            .onEnded { value in
                if value.translation.height < -30 || value.predictedEndTranslation.height < -80 {
                    onDismiss()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        dragOffset = 0
                    }
                }
            }
    }

    var body: some View {
        HStack(spacing: 4) {
            openButton

            closeButton
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: shape)
        .overlay {
            shape
                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        .offset(y: dragOffset)
        .gesture(swipeToDismiss)
    }
}
#endif
