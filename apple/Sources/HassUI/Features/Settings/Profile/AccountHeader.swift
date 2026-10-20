import HassCore
import HassDesign
import SwiftUI

/// The signed-in person at the top of the Profile tab, centred as in Apple's account sheets (direction G mockup n1
/// profile): a large monogram, their name and the server they are signed in to.
struct AccountHeader: View {
    var name: String?
    var server: String
    @ScaledMetric(relativeTo: .largeTitle) private var avatarSize: CGFloat = 84

    var body: some View {
        VStack(spacing: HassTokens.Spacing.s) {
            Text(ProfileButton.initials(name) ?? "")
                .font(.system(size: avatarSize * 0.4, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(width: avatarSize, height: avatarSize)
                .background(HassTokens.Ink.actionFill, in: Circle())
                .overlay { if ProfileButton.initials(name) == nil { Image(systemName: "person.fill").font(.largeTitle).foregroundStyle(.white) } }
                .accessibilityHidden(true)
            Text(name ?? "Signed In")
                .font(.title2.weight(.bold))
                .foregroundStyle(HassTokens.Ink.primary)
                .multilineTextAlignment(.center)
            Text(server)
                .font(.subheadline)
                .foregroundStyle(HassTokens.Ink.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, HassTokens.Spacing.s)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("account.header")
    }
}
