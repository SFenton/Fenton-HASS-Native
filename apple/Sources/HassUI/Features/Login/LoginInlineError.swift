import HassDesign
import SwiftUI

/// The red line under the fields for a refused password or an account that needs two-step sign-in: a warning glyph and the
/// sentence. The glyph keeps the message from resting on colour alone.
struct LoginInlineError: View {
    var message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.subheadline)
            .foregroundStyle(Color(rgb: SignInStyle.error))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, HassTokens.Spacing.s)
            .accessibilityIdentifier("login.error")
    }
}
