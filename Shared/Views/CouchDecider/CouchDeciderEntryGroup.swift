//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

/// The "What should we watch?" button on a group couch's home.
///
/// iOS: the first row, a full-width glass card.
/// tvOS: directly below the cinematic hero, a focusable card.
struct CouchDeciderEntryGroup: ContentGroup {

    let couch: CouchGroup
    let id: String = "couch-decider"

    func body(with viewModel: Empty) -> Body {
        Body(couch: couch)
    }

    struct Body: View {

        @Default(.accentColor)
        private var accentColor

        @Router
        private var router

        let couch: CouchGroup

        private var iconSize: CGFloat {
            UIDevice.isTV ? 90 : 48
        }

        var body: some View {
            Button {
                router.route(to: .couchDecider(couch: couch))
            } label: {
                label
            }
            .foregroundStyle(.primary, .secondary)
            #if os(tvOS)
            .buttonStyle(.card)
            #else
            .buttonStyle(.plain)
            #endif
            .edgePadding(.horizontal)
            .focusSection()
            .accessibilityLabel(L10n.CouchDecider.whatShouldWeWatch)
            .accessibilityHint(L10n.CouchDecider.letCouchfinPick(couch.displayNames))
        }

        @ViewBuilder
        private var label: some View {
            HStack(spacing: UIDevice.isTV ? 32 : 14) {
                icon

                VStack(alignment: .leading, spacing: UIDevice.isTV ? 6 : 2) {
                    Text(L10n.CouchDecider.whatShouldWeWatch)
                        .font(UIDevice.isTV ? .title3 : .headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(L10n.CouchDecider.letCouchfinPick(couch.displayNames))
                        .font(UIDevice.isTV ? .callout : .subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.forward")
                    .font(UIDevice.isTV ? .title3 : .body)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
            .padding(UIDevice.isTV ? 32 : 14)
            #if os(tvOS)
            .frame(width: 960, alignment: .leading)
            #else
            .frame(maxWidth: .infinity, alignment: .leading)
            #endif
            #if os(iOS)
            .backport
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            #endif
        }

        private var icon: some View {
            Image(systemName: "dice.fill")
                .font(.system(size: iconSize * 0.48, weight: .semibold))
                .foregroundStyle(accentColor.overlayColor)
                .frame(width: iconSize, height: iconSize)
                .background(accentColor, in: .circle)
                .accessibilityHidden(true)
        }
    }
}
