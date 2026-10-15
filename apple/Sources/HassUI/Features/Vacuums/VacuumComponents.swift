import HassCore
import HassDesign
import SwiftUI

// MARK: - Style

/// Colours and shapes local to the vacuum surfaces, all drawn from direction G's tokens
/// (`.agents/design/direction-g.md`, Colour; vacuums are the ``ColorFamily/cleaning`` family).
enum VacuumStyle {
    /// A status tone's glyph colour.
    static func color(_ tone: VacuumTone) -> Color {
        switch tone {
        case .active: ColorFamily.cleaning.glyph
        case .ok: .green
        case .returning: HassTokens.Ink.action
        case .warning: HassTokens.Ink.warning
        case .danger: HassTokens.Ink.danger
        case .neutral, .unavailable: HassTokens.Ink.secondary
        }
    }

    /// A command button's glyph colour: white on the primary capsule, the tone on the grey one.
    static func color(_ tone: VacuumController.ActionTone) -> Color {
        switch tone {
        case .primary: .white
        case .neutral: HassTokens.Ink.primary
        case .warning: HassTokens.Ink.warning
        case .danger: HassTokens.Ink.danger
        }
    }

    /// The SF Symbol for an MDI name.
    static func symbol(_ mdi: String) -> String { SymbolMap.symbol(for: mdi) }

    /// A selected room (map, room cards, order chips): a white ground with dark ink, the way the mockups draw a
    /// chosen room (direction G, Controls: Vacuum map).
    static let selectedFill = Color.white
    /// Ink and order badges on ``selectedFill``, and the badge ground everywhere: the sheet's `#1C1C1E`.
    static let selectedInk = Color(rgb: HassTokens.Palette.sheetGround)

    /// Grouped rows in the sheet: the sheet's cell colour at the module radius.
    static let groupShape = RoundedRectangle(cornerRadius: HassTokens.Radius.module, style: .continuous)
    /// Room cards (tile radius).
    static let cardShape = RoundedRectangle(cornerRadius: HassTokens.Radius.tile, style: .continuous)

    /// The secondary capsule's fill (Pause, Stop, Edit Area): the system's grey control fill.
    static var secondaryFill: AnyShapeStyle { AnyShapeStyle(.fill.secondary) }
}

// MARK: - Section

/// A titled block in the vacuum sheet: a 15 pt Semibold secondary header over the group it names, and an optional
/// footer (direction G, Type: "Over inset lists in sheets, 15 Semibold secondary"; web `ControlSection`).
struct VacuumSection<Content: View>: View {
    var title: String
    var footer: String?
    var content: Content

    init(_ title: String, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HassTokens.Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, HassTokens.Spacing.l)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            content
            if let footer { VacuumDescription(footer) }
        }
        .accessibilityElement(children: .contain)
    }
}

/// Supporting copy under a group, inset to its text (the 13 pt footer, direction G, Type).
struct VacuumDescription: View {
    var text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(HassTokens.Ink.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, HassTokens.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Rows

/// One row of a grouped list in the sheet: a leading glyph, a 17 pt title, an optional 15 pt subtitle and a trailing
/// accessory, at least 52 pt tall (60 with a subtitle; direction G, Controls: Lists).
struct VacuumListRow<Trailing: View>: View {
    var symbol: String
    var tint: Color
    var title: String
    var titleColor: Color
    var subtitle: String?
    /// The subtitle's ink: secondary on sheet cells, ``HassTokens/Surface/secondaryOnModule`` on the wallpaper.
    var subtitleColor: Color
    var trailing: Trailing
    @ScaledMetric(relativeTo: .body) private var glyphWidth: CGFloat = VacuumRowMetrics.glyphWidth

    init(symbol: String, tint: Color = HassTokens.Ink.secondary, title: String, titleColor: Color = HassTokens.Ink.primary,
         subtitle: String? = nil, subtitleColor: Color = HassTokens.Ink.secondary, @ViewBuilder trailing: () -> Trailing) {
        self.symbol = symbol
        self.tint = tint
        self.title = title
        self.titleColor = titleColor
        self.subtitle = subtitle
        self.subtitleColor = subtitleColor
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: VacuumRowMetrics.glyphGap) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: glyphWidth)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(titleColor)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(subtitleColor)
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, HassTokens.Spacing.l)
        .padding(.vertical, HassTokens.Spacing.s + 2)
        .frame(maxWidth: .infinity, minHeight: subtitle == nil ? 52 : 60, alignment: .leading)
        .contentShape(Rectangle())
    }
}

extension VacuumListRow where Trailing == EmptyView {
    init(symbol: String, tint: Color = HassTokens.Ink.secondary, title: String, titleColor: Color = HassTokens.Ink.primary,
         subtitle: String? = nil) {
        self.init(symbol: symbol, tint: tint, title: title, titleColor: titleColor, subtitle: subtitle) { EmptyView() }
    }
}

/// Row measurements shared by ``VacuumListRow`` and ``VacuumRowDivider``.
enum VacuumRowMetrics {
    /// The leading glyph's column at the default text size.
    static let glyphWidth: CGFloat = 28
    /// Between the glyph column and the text.
    static let glyphGap: CGFloat = 14
}

/// The hairline between two ``VacuumListRow``s, inset to their text.
struct VacuumRowDivider: View {
    @ScaledMetric(relativeTo: .body) private var glyphWidth: CGFloat = VacuumRowMetrics.glyphWidth

    var body: some View {
        Divider()
            .overlay(HassTokens.Surface.separator)
            .padding(.leading, HassTokens.Spacing.l + glyphWidth + VacuumRowMetrics.glyphGap)
    }
}

extension View {
    /// Draws a group of rows on the sheet's cell colour (direction G, Sheets: `#2C2C2E` cells, 26 pt corners).
    func vacuumGroup() -> some View {
        background(HassTokens.Surface.sheetCell, in: VacuumStyle.groupShape)
    }
}

// MARK: - Status chips

/// A read-only status capsule (Docked, 100%, Dock Idle): a toned glyph and the value, read as one element with its
/// label (pattern: `.agents/patterns/status-pill.md`; mockup n6-vacuum-sheet).
struct VacuumStatusChip: View {
    var symbol: String
    var tint: Color
    /// What VoiceOver names the chip ("Battery").
    var label: String
    var value: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(value)
                .foregroundStyle(HassTokens.Ink.primary)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.subheadline.weight(.semibold))
        .padding(.leading, 10)
        .padding(.trailing, HassTokens.Spacing.m)
        .padding(.vertical, HassTokens.Spacing.s)
        .frame(minHeight: 36)
        .background(HassTokens.Surface.sheetCell, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}

/// A selected room in cleaning order: a white capsule with a black numbered badge (mockup n6-vacuum-sheet).
struct VacuumOrderChip: View {
    var order: Int
    var title: String

    var body: some View {
        HStack(spacing: 6) {
            VacuumOrderBadge(order: order)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(VacuumStyle.selectedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 3)
        .padding(.trailing, 10)
        .padding(.vertical, 3)
        .background(VacuumStyle.selectedFill, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(order). \(title)")
    }
}

/// A room's cleaning order: a white numeral on a black disc.
struct VacuumOrderBadge: View {
    var order: Int
    @ScaledMetric(relativeTo: .subheadline) private var size: CGFloat = 24

    var body: some View {
        Text("\(order)")
            .font(.footnote.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .frame(minWidth: size, minHeight: size)
            .background(VacuumStyle.selectedInk, in: Circle())
            .accessibilityHidden(true)
    }
}

// MARK: - Action button

/// A command button (web `ActionButton`): the screen's one primary capsule (``PrimaryButtonStyle``) for a primary
/// action such as Clean, else a grey 50 pt capsule with a toned glyph (Pause, Stop, Dock).
struct VacuumActionButton: View {
    var action: VacuumController.Action
    /// Defaults to `vacuum.action.<kind>`.
    var identifier: String?
    /// Shows the action's detail under the button; it is always the button's hint.
    var showsDetail = true
    var perform: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.xs) {
            button
                .disabled(action.isDisabled)
                .accessibilityIdentifier(identifier ?? "vacuum.action.\(action.kind.rawValue)")
                .accessibilityHint(action.detail ?? "")
            if showsDetail, let detail = action.detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(HassTokens.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, HassTokens.Spacing.l)
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder private var button: some View {
        let base = Button(action: perform) {
            Label {
                Text(action.title)
            } icon: {
                Image(systemName: VacuumStyle.symbol(action.icon))
                    .foregroundStyle(VacuumStyle.color(action.tone))
            }
        }
        if action.tone == .primary {
            base.buttonStyle(PrimaryButtonStyle())
        } else {
            base.buttonStyle(VacuumSecondaryButtonStyle())
        }
    }
}

/// The grey 50 pt capsule for commands that are not the screen's primary action (mockup n6-vacuum-cleaning: Pause
/// and Stop). The label stays in the primary ink; the glyph carries the tone (orange and red text fail contrast).
struct VacuumSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration)
    }

    private struct StyledLabel: View {
        var configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.body.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(HassTokens.Ink.primary)
                .padding(.horizontal, HassTokens.Spacing.l)
                .padding(.vertical, HassTokens.Spacing.s)
                .frame(maxWidth: .infinity, minHeight: PrimaryButtonStyle.height)
                .background(VacuumStyle.secondaryFill, in: Capsule())
                .contentShape(Capsule())
                .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
        }
    }
}

// MARK: - Setting row

/// A select entity as a row (web `SelectSetting`; direction G, Controls: Choosing one option): two to four options
/// are a system segmented control, anything longer (and every setting at accessibility sizes, where segments cannot
/// grow) a pop-up menu anchored on the value, such as a five-step suction list.
///
/// In the menu form only the trailing value is the menu's button. The whole row used to be the `Menu` label, and
/// iOS hides a menu's source while the menu is open, so the row vanished from the sheet (owner report, 2026-10-13).
/// HIG: Segmented controls, Pop-up buttons.
struct VacuumSettingRow: View {
    var setting: VacuumController.Setting
    var onSelect: (String) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Whether `setting` draws as a segmented control: two to four options, at non-accessibility sizes.
    static func usesSegments(_ setting: VacuumController.Setting, accessibilitySize: Bool) -> Bool {
        !accessibilitySize && (2...4).contains(setting.options.count)
    }

    /// Whether every option's label is short enough ("2x") for a compact control beside the title.
    static func segmentsFitBesideTitle(_ setting: VacuumController.Setting) -> Bool {
        setting.options.allSatisfy { setting.label(for: $0).count <= 3 }
    }

    private var selection: Binding<String> {
        Binding(get: { setting.value }, set: onSelect)
    }

    private var symbol: String { VacuumStyle.symbol(setting.icon) }

    var body: some View {
        Group {
            if Self.usesSegments(setting, accessibilitySize: typeSize.isAccessibilitySize) {
                if Self.segmentsFitBesideTitle(setting) {
                    VacuumListRow(symbol: symbol, title: setting.title, subtitle: setting.detail) {
                        segments.frame(maxWidth: 170)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        VacuumListRow(symbol: symbol, title: setting.title, subtitle: setting.detail)
                        segments
                            .padding(.horizontal, HassTokens.Spacing.l)
                            .padding(.bottom, HassTokens.Spacing.m)
                    }
                }
            } else {
                menuRow
            }
        }
        .disabled(setting.isDisabled)
    }

    private var segments: some View {
        Picker(setting.title, selection: selection) {
            ForEach(setting.options, id: \.self) { Text(setting.label(for: $0)).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.large)
        .accessibilityIdentifier("vacuum.setting.\(setting.title)")
    }

    private var menu: some View {
        Menu {
            Picker(setting.title, selection: selection) {
                ForEach(setting.options, id: \.self) { Text(setting.label(for: $0)).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            // A menu picker's own button is about 34 pt tall; this label keeps the 44 pt target.
            HStack(spacing: HassTokens.Spacing.xs) {
                Text(setting.valueLabel)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote.weight(.semibold))
                    .accessibilityHidden(true)
            }
            // The pop-up's value is a text action: G's `#409CFF` on dark (direction G, Colour).
            .foregroundStyle(setting.isDisabled ? HassTokens.Ink.secondary : HassTokens.Ink.action)
            .frame(minHeight: HassTokens.minTarget)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(setting.title)
        .accessibilityValue(setting.valueLabel)
        .accessibilityIdentifier("vacuum.setting.\(setting.title)")
    }

    @ViewBuilder private var menuRow: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 0) {
                // The menu carries the title as its name.
                VacuumListRow(symbol: symbol, title: setting.title, subtitle: setting.detail)
                    .accessibilityHidden(true)
                menu
                    .padding(.horizontal, HassTokens.Spacing.l)
                    .padding(.bottom, HassTokens.Spacing.s)
            }
        } else {
            VacuumListRow(symbol: symbol, title: setting.title, subtitle: setting.detail) { menu }
        }
    }
}
