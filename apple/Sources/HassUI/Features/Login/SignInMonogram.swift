import FentonActivityModel
import HassCore
import HassDesign
import SwiftUI

/// The person's monogram on a disc in the icon's colours, for the welcome back sign-in.
struct SignInMonogram: View {
    var name: String?
    var icon: AppIconChoice
    var size: CGFloat = 88

    var body: some View {
        ZStack {
            Circle().fill(Color(rgb: icon.glyph))
            if let initials = ProfileButton.initials(name) {
                Text(initials)
                    .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(rgb: icon.tint))
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.42))
                    .foregroundStyle(Color(rgb: icon.tint))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
