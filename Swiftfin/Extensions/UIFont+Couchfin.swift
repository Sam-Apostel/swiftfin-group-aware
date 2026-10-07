//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import UIKit

extension UIFont {

    /// SF Pro Rounded, Couchfin's voice for titles, scaled with Dynamic Type.
    static func couchfinRounded(size: CGFloat, weight: UIFont.Weight, relativeTo style: UIFont.TextStyle) -> UIFont {
        let font = UIFont.systemFont(ofSize: size, weight: weight)
        let rounded = font.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? font

        return UIFontMetrics(forTextStyle: style).scaledFont(for: rounded)
    }
}
