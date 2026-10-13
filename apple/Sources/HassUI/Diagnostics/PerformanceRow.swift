import HassDesign
import SwiftUI

/// One measured value: a title, the headline value and a detail line.
struct PerformanceRow: View {
    enum Tone { case neutral, good, warning, bad }

    var title: String
    var value: String
    var detail: String
    var tone: Tone = .neutral

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.xs) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.body)
                    Spacer(minLength: HassTokens.Spacing.m)
                    valueText
                }
                VStack(alignment: .leading, spacing: HassTokens.Spacing.xs) {
                    Text(title).font(.body)
                    valueText
                }
            }
            Text(detail)
                .font(.footnote)
                .foregroundStyle(HassTokens.Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, HassTokens.Spacing.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(value). \(detail)")
    }

    private var valueText: some View {
        Text(value)
            .font(.body.monospacedDigit().weight(.semibold))
            .foregroundStyle(color)
    }

    private var color: Color {
        switch tone {
        // Only a bad value takes color; the number itself carries the rest (never color alone, HIG Color).
        case .neutral, .good, .warning: HassTokens.Ink.primary
        case .bad: HassTokens.Ink.danger
        }
    }
}
