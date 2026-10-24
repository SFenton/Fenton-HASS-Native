import HassDesign
import SwiftUI

/// The grouped-sheet colours the location permission screen draws with, so its status cell sits on the modal
/// background (`modalChrome()`) like a grouped list cell.
enum LocationPermissionColors {
    /// The inset cell colour on that background.
    static var cell: Color {
        HassTokens.Surface.systemCell
    }
}
