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

#Preview("Primary buttons") {
    VStack(spacing: 16) {
        PrimaryButton("Add to Groceries", systemImage: "cart.badge.plus") {}
        PrimaryButton("Start Watering", family: .water) {}
        PrimaryButton("Save") {}.disabled(true)
    }
    .padding()
    .background(Color(rgb: HassTokens.Palette.sheetGround))
}
