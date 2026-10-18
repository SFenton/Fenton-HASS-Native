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
                // A button, not a DisclosureGroup: the whole row is the 44 pt target and says whether it is open.
                Button(action: toggleDetail) {
                    HStack {
                        Text(LoginCopy.detailsTitle)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(showsDetail ? 90 : 0))
                            .accessibilityHidden(true)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(minHeight: HassTokens.minTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(showsDetail ? "Expanded" : "Collapsed")
                .accessibilityIdentifier("login.error.details")
                if showsDetail {
                    Text(detail)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.white.opacity(0.88))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("login.error.detail")
                }
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

    private func toggleDetail() {
        withAnimation(MotionTokens.quick) { showsDetail.toggle() }
    }
}
