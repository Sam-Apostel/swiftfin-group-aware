//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import SwiftUI

@propertyWrapper
struct Toaster: DynamicProperty {

    @EnvironmentObject
    private var toastProxy: ToastProxy

    var wrappedValue: ToastProxy {
        toastProxy
    }
}

@MainActor
class ToastProxy: ObservableObject {

    @Published
    var isPresenting: Bool = false
    @Published
    private(set) var systemName: String? = nil
    @Published
    private(set) var title: Text = Text(String.empty)

    private let pokeTimer = PokeIntervalTimer(defaultInterval: 2)
    private var pokeCancellable: AnyCancellable?

    init() {
        pokeCancellable = pokeTimer
            .sink { [weak self] in
                self?.dismiss()
            }
    }

    /// - Parameter duration: how long the toast stays, in seconds.
    func present(_ title: String, systemName: String? = nil, duration: TimeInterval = 2) {
        present(Text(title), systemName: systemName, duration: duration)
    }

    /// - Parameter duration: how long the toast stays, in seconds.
    func present(_ title: Text, systemName: String? = nil, duration: TimeInterval = 2) {
        self.title = title
        self.systemName = systemName

        poke(equalsPrevious: title == self.title, duration: duration)
    }

    private func poke(equalsPrevious: Bool, duration: TimeInterval) {
        withAnimation(.easeInOut(duration: 0.2)) {
            isPresenting = true
        }

        pokeTimer.poke(interval: duration)
    }

    func dismiss() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isPresenting = false
        }
    }
}
