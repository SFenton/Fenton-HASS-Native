import SwiftUI

/// A settings page section: a header, its description paragraphs and the controls they describe
/// (web `src/components/core/SettingsSection.tsx`; pattern: `.agents/patterns/settings-section.md`).
public struct SettingsSection<Content: View>: View {
    public var title: String
    public var paragraphs: [String]
    @ViewBuilder public var content: Content

    /// Creates a section.
    /// - Parameters:
    ///   - title: The header, exposed to VoiceOver as a heading.
    ///   - paragraphs: Description paragraphs, shown in order above the content.
    ///   - content: The section's controls.
    public init(title: String, paragraphs: [String], @ViewBuilder content: () -> Content) {
        self.title = title
        self.paragraphs = paragraphs
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(HassTokens.Ink.primary)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph)
                    .font(.subheadline)
                    .foregroundStyle(HassTokens.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content
                .padding(.top, HassTokens.Spacing.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A warning shown inline under the control it concerns (web `InlineAlert`).
public struct InlineAlert: View {
    public var message: String

    /// Creates an alert.
    public init(_ message: String) { self.message = message }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: HassTokens.Spacing.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(HassTokens.Ink.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(HassTokens.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: HassTokens.Radius.chip, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Warning: \(message)")
    }
}

/// One choice in a single-choice list: icon, label and what it does, with a checkmark on the selected one
/// (web `ScheduleListRow` in the presence override detail; pattern: `.agents/patterns/settings-section.md`).
public struct SelectableOptionRow: View {
    public var title: String
    public var detail: String
    public var symbol: String
    public var tint: Color
    public var isSelected: Bool
    public var isDisabled: Bool
    public var action: () -> Void

    /// Creates a row.
    public init(title: String, detail: String, symbol: String, tint: Color, isSelected: Bool, isDisabled: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.tint = tint
        self.isSelected = isSelected
        self.isDisabled = isDisabled
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: HassTokens.Spacing.m) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(isSelected ? tint : .secondary)
                    .frame(minWidth: 28)
                VStack(alignment: .leading, spacing: HassTokens.Spacing.xs) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(HassTokens.Ink.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(HassTokens.Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(tint)
                    .opacity(isSelected ? 1 : 0)
            }
            .padding(HassTokens.Spacing.m)
            .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: HassTokens.Radius.tile, style: .continuous)
                    .fill(.regularMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: HassTokens.Radius.tile, style: .continuous)
                    .strokeBorder(isSelected ? tint : .clear, lineWidth: 2)
            }
            .opacity(isDisabled ? 0.5 : 1)
            .contentShape(RoundedRectangle(cornerRadius: HassTokens.Radius.tile, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint(detail)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
