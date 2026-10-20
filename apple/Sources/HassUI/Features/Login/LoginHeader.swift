import FentonActivityModel
import HassCore
import HassDesign
import SwiftUI

/// The top of the sign-in screen: the bare house-and-heart mark, "S+H" and one line; or, for a session that ended, the
/// person's monogram, "Welcome back, <first name>" and a line about the password.
struct LoginHeader: View {
    var mode: LoginModel.Mode
    var icon: AppIconChoice
    /// The mark's (or monogram's) scale and whether it is shown yet, for the intro.
    var markScale: CGFloat
    var markShown: Bool

    var body: some View {
        VStack(spacing: HassTokens.Spacing.s) {
            switch mode {
            case .fresh:
                SignInMark(icon: icon)
                    .scaleEffect(markScale)
                    .opacity(markShown ? 1 : 0)
                    .padding(.bottom, HassTokens.Spacing.m)
                Text(LoginCopy.appName)
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                    .accessibilityLabel(AppBranding.spokenName)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("login.title")
                line(LoginCopy.subtitle)
            case let .welcomeBack(account):
                SignInMonogram(name: account.name, icon: icon)
                    .scaleEffect(markScale)
                    .opacity(markShown ? 1 : 0)
                    .padding(.bottom, HassTokens.Spacing.m)
                Text(LoginCopy.welcomeBack(account.firstName))
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("login.title")
                line(LoginCopy.welcomeSubtitle)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(HassTokens.Surface.secondaryOnWallpaper)
            .multilineTextAlignment(.center)
    }
}
