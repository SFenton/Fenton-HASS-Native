import HassDesign
import SwiftUI

/// A capsule filled with its tint (16% on a dark sheet, 8% on a light one, where the red label then holds 4.5:1 or
/// better) and labelled in the tint: the sheet's secondary destructive action.
struct TintedCapsuleButtonStyle: ButtonStyle {
    var tint: Color
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .foregroundStyle(tint)
            .padding(.horizontal, HassTokens.Spacing.xl)
            .padding(.vertical, HassTokens.Spacing.s)
            .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget)
            .background(tint.opacity(scheme == .light ? 0.08 : 0.16), in: Capsule())
            .contentShape(Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
    }
}
