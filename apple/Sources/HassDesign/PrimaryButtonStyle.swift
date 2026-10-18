import SwiftUI

/// The look of ``PrimaryButton``, for a `Button` that needs its own label (an ``ArcSpinner`` while sending).
public struct PrimaryButtonStyle: ButtonStyle {
    /// The button's height, and twice its corner radius.
    public static let height: CGFloat = 50

    private let family: ColorFamily?

    /// Creates the style.
    /// - Parameter family: An owner's colour family to fill with instead of the tint.
    public init(family: ColorFamily? = nil) {
        self.family = family
    }

    public func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonBody(configuration: configuration, colors: Self.colors(family))
    }

    /// The fill and label colours: the tint with white, or a family's glyph colour with dark text. Both are fixed, in
    /// light and dark sheets alike (the family's dark-appearance glyph, not its light-sheet variant).
    static func colors(_ family: ColorFamily?) -> (fill: Color, label: Color) {
        guard let family else { return (HassTokens.Ink.actionFill, .white) }
        return (Color(rgb: family.spec.glyph), Color(rgb: HassTokens.Palette.sheetGround))
    }
}

/// Reads `isEnabled`, which a `ButtonStyle` cannot.
private struct PrimaryButtonBody: View {
    var configuration: ButtonStyleConfiguration
    var colors: (fill: Color, label: Color)
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .stateForeground("PrimaryButton", colors.label)
            .padding(.horizontal, HassTokens.Spacing.xl)
            .padding(.vertical, HassTokens.Spacing.s)
            .frame(maxWidth: .infinity, minHeight: PrimaryButtonStyle.height)
            .background {
                RoundedRectangle(cornerRadius: PrimaryButtonStyle.height / 2, style: .continuous)
                    .fill(colors.fill)
                    .stateColorTransition("PrimaryButton", value: colors.fill)
            }
            .contentShape(RoundedRectangle(cornerRadius: PrimaryButtonStyle.height / 2, style: .continuous))
            // Enabling or disabling the button fades with `quick`; the press dim stays immediate.
            .opacity(isEnabled ? 1 : 0.4)
            .quickTransition("PrimaryButton", value: isEnabled)
            .opacity(isEnabled && configuration.isPressed ? 0.8 : 1)
    }
}
