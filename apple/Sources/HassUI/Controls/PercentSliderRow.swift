import HassDesign
import SwiftUI

/// A labelled 0...100 slider in steps of 5 that shows and speaks its value (web `RangeField`).
struct PercentSliderRow: View {
    var title: String
    @Binding var value: Double
    var identifier: String
    @Environment(\.isEnabled) private var isEnabled

    init(_ title: String, value: Binding<Double>, identifier: String) {
        self.title = title
        _value = value
        self.identifier = identifier
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).foregroundStyle(HassTokens.Ink.primary)
                Spacer(minLength: HassTokens.Spacing.s)
                Text("\(Int(value))%").monospacedDigit().foregroundStyle(HassTokens.Ink.secondary)
            }
            Slider(value: $value, in: 0...100, step: 5)
        }
        .padding(.vertical, HassTokens.Spacing.xs)
        .opacity(isEnabled ? 1 : 0.5)
        // One adjustable element for the row: the visible title and value belong to it (hiding them while only
        // the slider spoke flagged "potentially inaccessible text" on the folded iPhone Duo).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(Int(value)) percent")
        .accessibilityAdjustableAction { direction in
            guard isEnabled else { return }
            value = Self.adjusted(value, direction)
        }
        .accessibilityIdentifier(identifier)
    }

    /// The value after a VoiceOver swipe: steps of 5 within 0...100.
    static func adjusted(_ value: Double, _ direction: AccessibilityAdjustmentDirection) -> Double {
        switch direction {
        case .increment: min(100, value + 5)
        case .decrement: max(0, value - 5)
        @unknown default: value
        }
    }
}
