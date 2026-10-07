//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

/// Couchfin's empty state: the fin, one line, one action.
struct FinEmptyView<Actions: View>: View {

    private let title: String
    private let description: String?
    private let actions: Actions

    init(
        _ title: String,
        description: String? = nil,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.description = description
        self.actions = actions()
    }

    private var finWidth: CGFloat {
        UIDevice.isTV ? 520 : 240
    }

    var body: some View {
        VStack(spacing: UIDevice.isTV ? 28 : 14) {
            FinView()
                .frame(width: finWidth)
                .rotationEffect(.degrees(-6))
                .padding(.bottom, UIDevice.isTV ? 20 : 8)

            Text(title)
                .font(.system(.title2, design: .rounded, weight: .heavy))
                .multilineTextAlignment(.center)

            if let description {
                Text(description)
                    .font(.body)
                    .foregroundStyle(Color.Couchfin.mist)
                    .multilineTextAlignment(.center)
            }

            actions
                .padding(.top, 6)
        }
        .edgePadding(.horizontal)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}

extension FinEmptyView where Actions == EmptyView {

    init(_ title: String, description: String? = nil) {
        self.init(title, description: description) {
            EmptyView()
        }
    }
}
