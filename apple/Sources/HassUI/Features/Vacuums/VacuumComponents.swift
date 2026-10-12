import HassCore
import HassDesign
import SwiftUI

// MARK: - Style

/// Colors local to the vacuum surfaces (web `VACUUM_COLOR` and status pill tones).
enum VacuumStyle {
    /// Auto-clean tile tint (web `rgba(67,160,71,0.6)`).
    static let autoClean = Color(red: 0.26, green: 0.63, blue: 0.28)
    /// Cleaning (web teal).
    static let cleaning = Color(red: 0.0, green: 0.59, blue: 0.53)

    /// A tone's color.
    static func color(_ tone: VacuumTone) -> Color {
        switch tone {
        case .active: cleaning
        case .ok: Color.green
        case .returning: Color.blue
        case .warning: Color.orange
        case .danger: Color.red
        case .neutral: HassTokens.Ink.secondary
        case .unavailable: HassTokens.Ink.secondary
        }
    }

    /// A button tone's color.
    static func color(_ tone: VacuumController.ActionTone) -> Color {
        switch tone {
        case .primary: primaryFill
        case .neutral: HassTokens.Ink.primary
        case .warning: Color.orange
        case .danger: Color.red
        }
    }

    /// Primary button and order-badge fill: white text is 6.0:1 on it, so the small bold badge digits still clear
    /// the accessibility audit once anti-aliased (they measured 4.5:1 on the 5.2:1 fill, iPhone 2026-10-12).
    static let primaryFill = Color(red: 0.0, green: 0.38, blue: 0.76)

    /// The SF Symbol for an MDI name.
    static func symbol(_ mdi: String) -> String { SymbolMap.symbol(for: mdi) }

    /// Fill behind rows and pills; sits on the sheet background so it keeps its edge.
    static let rowFill = Color.primary.opacity(0.07)
    static let rowShape = RoundedRectangle(cornerRadius: 14, style: .continuous)
}

// MARK: - Section

/// A titled block in a vacuum tab (web `ControlSection` / `SectionHeader`).
struct VacuumSection<Content: View>: View {
    var title: String
    var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.m) {
            Text(title)
                .font(.headline)
                .foregroundStyle(HassTokens.Ink.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .accessibilityElement(children: .contain)
    }
}

/// Supporting copy under a section title.
struct VacuumDescription: View {
    var text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(HassTokens.Ink.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Pills

/// A labelled value with an icon (web `StatusPill`), read as one element.
struct VacuumInfoPill: View {
    var icon: String
    var label: String
    var value: String
    var tone: VacuumTone = .neutral

    var body: some View {
        HStack(spacing: HassTokens.Spacing.s) {
            Image(systemName: VacuumStyle.symbol(icon))
                .font(.body.weight(.semibold))
                .foregroundStyle(VacuumStyle.color(tone))
                .frame(minWidth: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(HassTokens.Ink.secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HassTokens.Ink.primary)
                    .monospacedDigit()
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, HassTokens.Spacing.m)
        .padding(.vertical, HassTokens.Spacing.s)
        .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget + 8, alignment: .leading)
        .background(VacuumStyle.rowFill, in: VacuumStyle.rowShape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}

// MARK: - Action button

/// A command button with optional help text (web `ActionButton`).
struct VacuumActionButton: View {
    var action: VacuumController.Action
    /// Defaults to `vacuum.action.<kind>`.
    var identifier: String?
    var perform: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.xs) {
            Button(action: perform) {
                HStack(spacing: HassTokens.Spacing.s) {
                    Image(systemName: VacuumStyle.symbol(action.icon))
                        .foregroundStyle(action.tone == .primary ? Color.white : VacuumStyle.color(action.tone))
                    Text(action.title)
                }
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget)
            }
            .buttonStyle(VacuumButtonStyle(tone: action.tone))
            .disabled(action.isDisabled)
            .accessibilityIdentifier(identifier ?? "vacuum.action.\(action.kind.rawValue)")
            .accessibilityHint(action.detail ?? "")
            if let detail = action.detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(HassTokens.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// Filled for primary, tinted for the rest; dimmed while disabled.
struct VacuumButtonStyle: ButtonStyle {
    var tone: VacuumController.ActionTone

    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration, tone: tone)
    }

    private struct StyledLabel: View {
        var configuration: Configuration
        var tone: VacuumController.ActionTone
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let color = VacuumStyle.color(tone)
            configuration.label
                // Text stays in the label color (orange and red text fail contrast); the icon carries the tone.
                .foregroundStyle(tone == .primary ? Color.white : HassTokens.Ink.primary)
                .padding(.horizontal, HassTokens.Spacing.m)
                .background(tone == .primary ? AnyShapeStyle(color) : AnyShapeStyle(VacuumStyle.rowFill), in: VacuumStyle.rowShape)
                .contentShape(VacuumStyle.rowShape)
                .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
        }
    }
}

// MARK: - Notices

/// A titled note (web `VacuumStatusNotice` / `InfoBox` / `InlineAlert`).
struct VacuumNotice<Content: View>: View {
    var title: String?
    var tone: VacuumTone
    var content: Content

    init(_ title: String?, tone: VacuumTone = .neutral, @ViewBuilder content: () -> Content) {
        self.title = title
        self.tone = tone
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .top, spacing: HassTokens.Spacing.s) {
            Image(systemName: tone == .warning || tone == .danger ? "exclamationmark.triangle.fill" : (tone == .ok ? "checkmark.circle.fill" : "info.circle.fill"))
                .foregroundStyle(tone == .neutral ? Color.accentColor : VacuumStyle.color(tone))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: HassTokens.Spacing.xs) {
                if let title {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(HassTokens.Ink.primary)
                }
                content
                    .font(.subheadline)
                    .foregroundStyle(HassTokens.Ink.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(HassTokens.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VacuumStyle.rowFill, in: VacuumStyle.rowShape)
        .accessibilityElement(children: .combine)
    }
}

extension VacuumNotice where Content == Text {
    init(_ title: String?, tone: VacuumTone = .neutral, text: String) {
        self.init(title, tone: tone) { Text(text) }
    }
}

// MARK: - Select row

/// A select entity as a menu row (web `SelectSetting`).
struct VacuumSettingRow: View {
    var setting: VacuumController.Setting
    var hideTitle = false
    var onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.xs) {
            Menu {
                Picker(setting.title, selection: Binding(get: { setting.value }, set: onSelect)) {
                    ForEach(setting.options, id: \.self) { Text(setting.label(for: $0)).tag($0) }
                }
            } label: {
                HStack(spacing: HassTokens.Spacing.s) {
                    Image(systemName: VacuumStyle.symbol(setting.icon))
                        .foregroundStyle(HassTokens.Ink.secondary)
                        .accessibilityHidden(true)
                    if !hideTitle {
                        Text(setting.title).foregroundStyle(HassTokens.Ink.primary)
                    }
                    Spacer(minLength: HassTokens.Spacing.s)
                    Text(setting.valueLabel)
                        .fontWeight(.semibold)
                        .foregroundStyle(HassTokens.Ink.primary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(HassTokens.Ink.secondary)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, HassTokens.Spacing.m)
                .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget)
                .background(VacuumStyle.rowFill, in: VacuumStyle.rowShape)
                .contentShape(VacuumStyle.rowShape)
            }
            .disabled(setting.isDisabled)
            .opacity(setting.isDisabled ? 0.45 : 1)
            .accessibilityLabel(setting.title)
            .accessibilityValue(setting.valueLabel)
            .accessibilityIdentifier("vacuum.setting.\(setting.title)")
            if let detail = setting.detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(HassTokens.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
        }
    }
}
