import HassCore
import HassDesign
import SwiftUI

/// Colors and small views shared by the wake-light and bed sheets.
enum BedroomStyle {
    /// Bed tile fills (web `EIGHT_SLEEP_*_BG`).
    static let heating = Color(red: 136 / 255, green: 64 / 255, blue: 26 / 255)
    static let cooling = Color(red: 25 / 255, green: 84 / 255, blue: 130 / 255)
    static let idle = Color(red: 67 / 255, green: 160 / 255, blue: 71 / 255)
    /// Stop buttons: a deep red that keeps white labels at about 6:1 (system red gives 3.6:1 and fails the audit).
    static let danger = Color(red: 0.76, green: 0.12, blue: 0.12)
    /// Primary actions (Add, Save): a deeper blue than the app accent, which leaves white labels at 2.5:1.
    static let action = Color(red: 0.0, green: 0.40, blue: 0.80)
    /// The power button while the side is off, and Snooze: a gray that keeps its white label above 4.5:1 (system gray does not).
    static let off = Color(white: 0.4)

    /// The tile tint for a bed action.
    static func tint(action: String) -> Color {
        switch action {
        case "heating": heating
        case "cooling": cooling
        default: idle
        }
    }

    /// A card background.
    static func card(_ content: some View) -> some View {
        content
            .padding(HassTokens.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: HassTokens.Radius.tile, style: .continuous))
    }
}

/// A section title (heading trait).
struct BedroomSectionHeader: View {
    var title: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.xs) {
            Text(title)
                .font(.headline)
                .foregroundStyle(HassTokens.Ink.primary)
                .accessibilityAddTraits(.isHeader)
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(HassTokens.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A tinted notice (web `Alert`/`InfoBox`).
struct BedroomNotice: View {
    enum Tone { case info, warning, error, success }

    var title: String?
    var message: String
    var tone: Tone = .warning

    private var color: Color {
        switch tone {
        case .info: .blue
        case .warning: .orange
        case .error: .red
        case .success: .green
        }
    }

    private var symbol: String {
        switch tone {
        case .info: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        case .success: "checkmark.circle.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: HassTokens.Spacing.m) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: HassTokens.Spacing.xs) {
                if let title {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(HassTokens.Ink.primary)
                }
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(HassTokens.Ink.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(HassTokens.Spacing.m)
        .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// A list row with an icon, title, detail lines and a trailing control (web `EightSleepAlarmGroupButton`,
/// wake-light schedule rows).
struct BedroomRow<Trailing: View>: View {
    var symbol: String
    var title: String
    var lines: [String]
    var isMuted = false
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: HassTokens.Spacing.m) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(isMuted ? HassTokens.Ink.secondary : HassTokens.Ink.primary)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(HassTokens.Ink.primary)
                ForEach(lines, id: \.self) { line in
                    Text(line).font(.subheadline).foregroundStyle(HassTokens.Ink.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
        .frame(minHeight: HassTokens.minTarget)
        .padding(.vertical, HassTokens.Spacing.s)
        .padding(.horizontal, HassTokens.Spacing.m)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// A grid of single-choice tiles (web radio tile grid for ramp and hold durations).
struct ChoiceGrid<Value: Hashable>: View {
    var title: String
    var options: [Value]
    var label: (Value) -> String
    @Binding var selection: Value
    var isDisabled = false
    var identifier: String
    @ScaledMetric(relativeTo: .body) private var minWidth: CGFloat = 120

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(HassTokens.Ink.primary)
            DynamicGridLayout(minCellWidth: minWidth, maxColumns: 5) {
                ForEach(options, id: \.self) { option in
                    let selected = option == selection
                    Button { selection = option } label: {
                        Text(label(option))
                            .font(.subheadline.weight(selected ? .semibold : .regular))
                            .foregroundStyle(selected ? Color.white : HassTokens.Ink.primary)
                            .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget)
                            .background(selected ? Color.accentColor : Color.primary.opacity(0.08),
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(label(option))
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                    .accessibilityIdentifier("\(identifier).\(option)")
                }
            }
            .disabled(isDisabled)
            .opacity(isDisabled ? 0.5 : 1)
        }
        .accessibilityElement(children: .contain)
    }
}

/// A Sunday–Saturday day picker (web day chips).
struct WeekdayPicker: View {
    var title: String
    @Binding var days: [Weekday]
    var identifier: String
    @ScaledMetric(relativeTo: .body) private var minWidth: CGFloat = 52

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(HassTokens.Ink.primary)
            DynamicGridLayout(minCellWidth: minWidth, maxColumns: 7) {
                ForEach(Weekday.allCases, id: \.self) { day in
                    let selected = days.contains(day)
                    Button {
                        days = Weekday.ordered(selected ? days.filter { $0 != day } : days + [day])
                    } label: {
                        Text(day.shortLabel)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selected ? Color.white : HassTokens.Ink.primary)
                            .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget)
                            .background(selected ? Color.accentColor : Color.primary.opacity(0.08), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(day.label)
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                    .accessibilityIdentifier("\(identifier).\(day.rawValue)")
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// An `HH:MM` time bound to a wheel/compact `DatePicker`.
struct ClockTimeField: View {
    var title: String
    @Binding var time: String
    var identifier: String

    var body: some View {
        DatePicker(title, selection: Binding(get: { Self.date(time) }, set: { time = Self.string($0) }),
                   displayedComponents: .hourAndMinute)
            .frame(minHeight: HassTokens.minTarget)
            .accessibilityIdentifier(identifier)
    }

    static func date(_ value: String) -> Date {
        let parts = value.split(separator: ":").compactMap { Int($0) }
        var components = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        components.hour = parts.first ?? 7
        components.minute = parts.count > 1 ? parts[1] : 0
        return Calendar.current.date(from: components) ?? .now
    }

    static func string(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}

/// A segmented tab picker that becomes a menu at accessibility sizes (the remote's tab pattern).
struct BedroomTabPicker<Tab: Hashable & Identifiable>: View {
    var label: String
    var tabs: [Tab]
    var title: (Tab) -> String
    @Binding var selection: Tab
    var identifier: String
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let picker = Picker(label, selection: $selection) {
            ForEach(tabs) { Text(title($0)).tag($0) }
        }
        .accessibilityIdentifier(identifier)
        if typeSize.isAccessibilitySize {
            picker.pickerStyle(.menu).frame(minHeight: HassTokens.minTarget)
        } else {
            picker.pickerStyle(.segmented).labelsHidden()
        }
    }
}

/// Sheet presentation shared by the bedroom sheets: full height and a page-size sheet on iPad, so landscape has
/// room for the hero beside the tabs.
extension View {
    func bedroomSheetPresentation() -> some View { mediaRemotePresentation() }
}

/// A once-a-second clock for countdowns.
struct EverySecond<Content: View>: View {
    @ViewBuilder var content: (Date) -> Content

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in content(context.date) }
    }
}
