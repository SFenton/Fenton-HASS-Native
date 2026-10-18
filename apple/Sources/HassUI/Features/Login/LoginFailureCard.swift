import HassDesign
import SwiftUI

/// The red card above the fields for a sign-in that did not reach Home Assistant or failed in a way the person cannot fix by
/// retyping: a plain-words title and body, and a Details disclosure with the raw reason (an HTTP code, a system error).
struct LoginFailureCard: View {
    var title: String
    var message: String
    var detail: String?

    @State private var showsDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                DisclosureGroup(LoginCopy.detailsTitle, isExpanded: $showsDetail) {
                    Text(detail)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.white.opacity(0.88))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, HassTokens.Spacing.xs)
                        .accessibilityIdentifier("login.error.detail")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .tint(.white)
                .accessibilityIdentifier("login.error.details")
            }
        }
        .padding(HassTokens.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(rgb: SignInStyle.error).opacity(0.16), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color(rgb: SignInStyle.error).opacity(0.45), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("login.error.card")
    }
}
