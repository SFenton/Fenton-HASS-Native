import SwiftUI

/// A labeled status value with a tone (web `StatusPill`, `src/components/core/StatusPill.tsx`;
/// pattern: `.agents/patterns/status-pill.md`).
///
/// Read-only: VoiceOver reads the label, then the value and detail, as one element.
public struct StatusPill: View {
    /// The icon's color (web `StatusPillTone`).
    public enum Tone: Sendable { case neutral, ok, active, warning, danger, unavailable }

    public var label: String
    public var value: String
    public var detail: String?
    public var symbol: String
    public var tone: Tone

    /// Creates a pill.
    public init(label: String, value: String, detail: String? = nil, symbol: String, tone: Tone = .neutral) {
        self.label = label
        self.value = value
        self.detail = detail
        self.symbol = symbol
        self.tone = tone
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: HassTokens.Spacing.s) {
            Image(systemName: symbol)
                .foregroundStyle(Self.color(tone))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.footnote)
                    .foregroundStyle(HassTokens.Ink.secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HassTokens.Ink.primary)
                    .monospacedDigit()
                if let detail {
                    Text(detail).font(.footnote).foregroundStyle(HassTokens.Ink.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(HassTokens.Spacing.m)
        .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: HassTokens.Radius.chip, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(Self.accessibilityValue(value: value, detail: detail))
    }

    /// `value, detail`, or just the value.
    nonisolated static func accessibilityValue(value: String, detail: String?) -> String {
        [value, detail].compactMap { $0 }.joined(separator: ", ")
    }

    /// The icon color for a tone.
    static func color(_ tone: Tone) -> Color {
        switch tone {
        case .neutral: HassTokens.Ink.secondary
        case .ok: .green
        case .active: HassTokens.Tint.water
        case .warning: .orange
        case .danger: .red
        case .unavailable: .gray
        }
    }
}
