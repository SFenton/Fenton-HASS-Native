import HassCore
import HassDesign
import SwiftUI

/// One icon in the grid: its art, its name, "Default" under the app's own icon and a check on the installed one.
///
/// A button named "Navy and Sky" (", default" for the default) whose value is "Selected" or "Not selected": the check
/// and the ring are not the only signal (HIG Accessibility: do not rely on colour alone).
struct AppIconChoiceButton: View {
    let choice: AppIconChoice
    let isSelected: Bool
    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 88
    private static let ringGap: CGFloat = 5

    var body: some View {
        Button(action: action) {
            VStack(spacing: HassTokens.Spacing.s) {
                AppIconPreview(choice: choice, side: side)
                    .padding(Self.ringGap)
                    .overlay {
                        RoundedRectangle(cornerRadius: side * AppIconPreview.cornerFraction + Self.ringGap, style: .continuous)
                            .strokeBorder(HassTokens.Ink.action.opacity(isSelected ? 1 : 0), lineWidth: 3)
                            .stateColorTransition("AppIconChoiceButton", value: isSelected)
                    }
                HStack(spacing: HassTokens.Spacing.xs) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(HassTokens.Ink.action)
                    }
                    Text(choice.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(HassTokens.Ink.primary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if choice.isDefault {
                    Text("Default")
                        .font(.caption)
                        .foregroundStyle(HassTokens.Surface.secondaryInSheet)
                }
            }
            .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.isDefault ? "\(choice.spokenName), default" : choice.spokenName)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityIdentifier("appIcon.choice.\(choice.rawValue)")
    }
}
