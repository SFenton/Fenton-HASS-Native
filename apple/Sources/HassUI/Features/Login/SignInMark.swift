import FentonActivityModel
import HassCore
import HassDesign
import SwiftUI

/// The bare house and heart, no tile and no container, in the house colour of the saved app icon. The heart's ring is cut out of
/// the house, so the ground shows through it.
struct SignInMark: View {
    var icon: AppIconChoice
    var size: CGFloat = 96

    var body: some View {
        HouseHeartShape()
            .fill(Color(rgb: icon.glyph))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
