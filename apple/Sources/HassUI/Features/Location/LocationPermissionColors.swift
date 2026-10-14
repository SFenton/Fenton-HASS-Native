import SwiftUI

/// The grouped-sheet colours the location permission screen draws with, so its cell and pinned action bar match
/// the modal background (`modalChrome()`).
enum LocationPermissionColors {
    /// The sheet's grouped background, behind the pinned action.
    static var ground: Color {
        #if canImport(UIKit)
        Color(uiColor: .systemGroupedBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    /// The inset cell colour on that background.
    static var cell: Color {
        #if canImport(UIKit)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }
}
