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
    /// Whether the title and subtitle have faded up yet, and how far they still sit below their place (0 under Reduce Motion).
    /// The mark has its own fade, so its rise is seen before the title arrives.
    var titleShown = true
    var titleRise: CGFloat = 0

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
                    .titleEntrance(shown: titleShown, rise: titleRise)
                line(LoginCopy.subtitle)
                    .titleEntrance(shown: titleShown, rise: titleRise)
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
                    .titleEntrance(shown: titleShown, rise: titleRise)
                line(LoginCopy.welcomeSubtitle)
                    .titleEntrance(shown: titleShown, rise: titleRise)
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

private extension View {
    /// Fades in and settles up from `rise` points below, while the mark above it is already on screen.
    func titleEntrance(shown: Bool, rise: CGFloat) -> some View {
        opacity(shown ? 1 : 0).offset(y: shown ? 0 : rise)
    }
}
