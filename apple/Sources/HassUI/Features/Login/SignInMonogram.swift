import FentonActivityModel
import HassCore
import HassDesign
import SwiftUI

/// The person's monogram on a disc in the icon's colours, for the welcome back sign-in.
struct SignInMonogram: View {
    var name: String?
    var icon: AppIconChoice
    /// The disc's diameter; it grows with the text size, like the initials in it.
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 88

    var body: some View {
        ZStack {
            Circle().fill(Color(rgb: icon.glyph))
            if let initials = ProfileButton.initials(name) {
                Text(initials)
                    .font(.system(.title, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color(rgb: icon.tint))
            } else {
                Image(systemName: "person.fill")
                    .font(.title)
                    .foregroundStyle(Color(rgb: icon.tint))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
