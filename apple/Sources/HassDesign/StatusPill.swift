import SwiftUI

/// A labeled status value with a tone (web `StatusPill`, `src/components/core/StatusPill.tsx`;
/// pattern: `.agents/patterns/status-pill.md`).
///
/// Read-only: VoiceOver reads the label, then the value and detail, as one element.
public struct StatusPill: View {
    /// The icon's color (web `StatusPillTone`).
    public enum Tone: Sendable { case neutral, ok, active, warning, danger, unavailable }

    /// What the pill is drawn on.
    public enum Surface: Sendable {
        /// A page: a material, like the tiles around it.
        case page
        /// A grouped list in a sheet: a solid row fill. A material over the sheet's glass smeared the
        /// content behind it.
        case groupedList
        /// A cell inside a direction G module on the wallpaper (``SwiftUICore/View/module(_:cornerRadius:)``), which
        /// draws the ground: no fill of its own.
        case module
    }

    public var label: String
    public var value: String
    public var detail: String?
    public var symbol: String
    public var tone: Tone
    public var surface: Surface

    /// Creates a pill.
    public init(label: String, value: String, detail: String? = nil, symbol: String, tone: Tone = .neutral,
                surface: Surface = .page) {
        self.label = label
        self.value = value
        self.detail = detail
        self.symbol = symbol
        self.tone = tone
        self.surface = surface
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: HassTokens.Spacing.s) {
            Image(systemName: symbol)
                .stateForeground("StatusPill", Self.color(tone))
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
        .background {
            RoundedRectangle(cornerRadius: HassTokens.Radius.chip, style: .continuous)
                .fill(fill)
                .stateColorTransition("StatusPill", value: tone)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(Self.accessibilityValue(value: value, detail: detail))
    }

    private var fill: AnyShapeStyle {
        switch surface {
        case .page: AnyShapeStyle(.regularMaterial)
        case .module: AnyShapeStyle(Color.clear)
        case .groupedList:
            #if os(iOS)
            AnyShapeStyle(Color(uiColor: .secondarySystemGroupedBackground))
            #else
            AnyShapeStyle(.background.secondary)
            #endif
        }
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
