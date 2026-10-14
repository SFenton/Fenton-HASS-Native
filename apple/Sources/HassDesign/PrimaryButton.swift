import SwiftUI

/// A screen's one primary action (`.agents/design/direction-g.md`, Controls: Primary buttons): a 50 pt capsule
/// filled with G's `#0071E3` and a white label, or, on a sheet about one owner's thing, that family's colour with
/// dark text (Sprinklers cyan). At most one per screen; there are no white or grey primary buttons.
///
/// HIG: [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons) ("Make the most likely
/// action the prominent one"). The label wraps and the button grows at large Dynamic Type rather than truncating.
public struct PrimaryButton: View {
    private let title: String
    private let systemImage: String?
    private let family: ColorFamily?
    private let action: () -> Void

    /// Creates a primary button.
    /// - Parameters:
    ///   - title: The action, in Title Case ("Start Watering").
    ///   - systemImage: An optional leading symbol.
    ///   - family: An owner's colour family to fill with instead of the tint; its glyph colour with dark text.
    ///   - action: What the button does.
    public init(_ title: String, systemImage: String? = nil, family: ColorFamily? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.family = family
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
        .buttonStyle(PrimaryButtonStyle(family: family))
    }
}

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

    /// The fill and label colours: the tint with white, or a family's glyph colour with dark text.
    static func colors(_ family: ColorFamily?) -> (fill: Color, label: Color) {
        guard let family else { return (HassTokens.Ink.actionFill, .white) }
        return (family.glyph, Color(rgb: HassTokens.Palette.sheetGround))
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
            .foregroundStyle(colors.label)
            .padding(.horizontal, HassTokens.Spacing.xl)
            .padding(.vertical, HassTokens.Spacing.s)
            .frame(maxWidth: .infinity, minHeight: PrimaryButtonStyle.height)
            .background(colors.fill, in: RoundedRectangle(cornerRadius: PrimaryButtonStyle.height / 2, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: PrimaryButtonStyle.height / 2, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
    }
}

#Preview("Primary buttons") {
    VStack(spacing: 16) {
        PrimaryButton("Add to Groceries", systemImage: "cart.badge.plus") {}
        PrimaryButton("Start Watering", family: .water) {}
        PrimaryButton("Save") {}.disabled(true)
    }
    .padding()
    .background(Color(rgb: HassTokens.Palette.sheetGround))
}
