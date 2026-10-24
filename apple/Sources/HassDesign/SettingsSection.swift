import SwiftUI

/// A settings page section: a header, its description paragraphs and the controls they describe
/// (web `src/components/core/SettingsSection.tsx`; pattern: `.agents/patterns/settings-section.md`).
public struct SettingsSection<Content: View>: View {
    public var title: String
    public var paragraphs: [String]
    @ViewBuilder public var content: Content
    @Environment(\.tileSurface) private var surface

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
                    // On the wallpaper (the Settings tab's topic pages) the fixed white ink: the adaptive secondary
                    // measured 4.1:1 there, and white at 85% 4.3:1 over a bright patch of the iPad's wallpaper (live Admin
                    // page, 2026-10-17); in a sheet it keeps the sheet's own ink.
                    .foregroundStyle(surface == .page ? HassTokens.Ink.onDark : HassTokens.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content
                .padding(.top, HassTokens.Spacing.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A warning or error shown inline under the control it concerns (web `InlineAlert`): the one inline alert for every
/// page (pattern: `.agents/patterns/info-box.md`).
///
/// A warning is primary ink on an orange wash, read as "Warning: …". An error is red text with no box, read as
/// "Error: …" (web `InlineAlert` error severity on the Vacation and Solo Trip pages).
public struct InlineAlert: View {
    /// How serious the alert is.
    public enum Severity: Sendable {
        case warning
        case error
    }

    public var message: String
    /// The leading symbol; the severity's own unless the alert has one (a low battery).
    public var symbol: String
    public var severity: Severity

    /// Creates an alert.
    public init(_ message: String, symbol: String? = nil, severity: Severity = .warning) {
        self.message = message
        self.severity = severity
        self.symbol = symbol ?? (severity == .error ? "exclamationmark.circle.fill" : "exclamationmark.triangle.fill")
    }

    public var body: some View {
        switch severity {
        case .warning:
            HStack(alignment: .firstTextBaseline, spacing: HassTokens.Spacing.s) {
                Image(systemName: symbol)
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
        case .error:
            Label {
                Text(message).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: symbol).accessibilityHidden(true)
            }
            .font(.subheadline)
            .foregroundStyle(HassTokens.Ink.error)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Error: \(message)")
        }
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
                    .stateForeground("SelectableOptionRow", isSelected ? tint : Color.secondary)
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
                    .quickTransition("SelectableOptionRow", value: isSelected)
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
                    .stateColorTransition("SelectableOptionRow", value: isSelected)
            }
            .opacity(isDisabled ? 0.5 : 1)
            .quickTransition("SelectableOptionRow", value: isDisabled)
            .contentShape(RoundedRectangle(cornerRadius: HassTokens.Radius.tile, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        // On the Button itself, so its identifier and selected state stay on one element (see GlassTile).
        .accessibilityLabel(title)
        // The description is content, not a hint: hints can be turned off.
        .accessibilityValue(detail)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
