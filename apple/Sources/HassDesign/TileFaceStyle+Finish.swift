import SwiftUI

/// Helpers the frosted finishes use to tell a filled or lit face from a neutral one.
extension TileFaceStyle {
    var isFilledOrLit: Bool {
        switch self {
        case .filled, .lit, .colored: true
        default: false
        }
    }
}
