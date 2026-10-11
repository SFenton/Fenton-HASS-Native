import HassCore
import HassDesign
import SwiftUI

// MARK: - Style

/// Colors and sizes local to the Climate page.
enum ClimateStyle {
    /// Heating `#cd5401` (web `THERMOSTAT_HEAT_COLOR`).
    static let heat = Color(hex: ClimateConfig.heatColorHex)
    /// Cooling `#2c8e98` (web `THERMOSTAT_COOL_COLOR`).
    static let cool = Color(hex: ClimateConfig.coolColorHex)
    /// Toggles and openers (web `tone="switch"`).
    static let control = HassTokens.Tint.climate
    /// An open vent (web `VENT_OPEN_COLOR`, rgb 30 136 229).
    static let ventOpen = Color(red: 30 / 255, green: 136 / 255, blue: 229 / 255)
    /// An open door or window.
    static let contact = HassTokens.Tint.contact

    /// The tint for an `hvac_action`: heat, cool, or `nil` when idle (web `thermostatActionColor`).
    static func tint(action: String) -> Color? {
        switch ThermostatThermalStatus(action: action) {
        case .heat: heat
        case .cool: cool
        default: nil
        }
    }

    /// The SF Symbol for an MDI icon name.
    static func symbol(_ mdi: String) -> String { SymbolMap.symbol(for: mdi) }
}

extension Color {
    /// A color from `0xRRGGBB`.
    init(hex: Int) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

// MARK: - Section

/// A section: heading, optional description, then content (web `SectionHeader` + `Description`).
struct ClimateSection<Content: View>: View {
    var title: String
    var description: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.m) {
            RemoteSectionHeader(title: title)
            if let description { ClimateDescription(text: description) }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Supporting copy above a control (web `Description`).
struct ClimateDescription: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(HassTokens.Ink.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A description followed by its control (web `ThermostatModalControl`).
struct ClimateControlGroup<Content: View>: View {
    var description: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
            ClimateDescription(text: description)
            content
        }
    }
}

// MARK: - Notice

/// An informational card (web `Notice` / `InlineAlert`), read as one element.
struct ClimateNotice: View {
    var text: String
    var symbol = "info.circle"
    var tint: Color = ClimateStyle.control

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: HassTokens.Spacing.m) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(HassTokens.Ink.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(HassTokens.Spacing.m)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: HassTokens.Radius.chip, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: HassTokens.Radius.chip, style: .continuous).strokeBorder(tint.opacity(0.4), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Toggle tile

/// A switch or input_boolean tile: optimistic on/off through ``ClimateController/toggle(_:)``
/// (web `ThermostatToggleSetting`).
struct ClimateToggleTile: View {
    var controller: ClimateController
    var entityId: String
    var title: String
    var icon: String

    var body: some View {
        let isOn = controller.isOn(entityId)
        RemoteGlassTile(
            title: title,
            subtitle: ClimateLogic.compactState(controller.entity(entityId), state: controller.shown(entityId)),
            symbol: ClimateStyle.symbol(icon),
            tint: ClimateStyle.control,
            isActive: isOn,
            isDisabled: controller.isUnavailable(entityId),
            semantics: .toggle(isOn: isOn)
        ) { controller.toggle(entityId) }
        .accessibilityIdentifier("climate.toggle.\(entityId)")
    }
}

/// A tile that opens a detail page (web `GlassTile disclosure`).
struct ClimateOpenerTile: View {
    var title: String
    var subtitle: String?
    var icon: String
    var isDisabled = false
    var action: () -> Void

    var body: some View {
        // Disabled, not unavailable: VoiceOver reads the subtitle ("Enable Track Selected Rooms first") and
        // "dimmed", rather than "Unavailable". `.disabled` outside so assistive technologies report it.
        GlassTile(title: title, subtitle: subtitle, symbol: ClimateStyle.symbol(icon), tint: ClimateStyle.control,
                  isActive: false, kind: .navigate, action: action)
            .disabled(isDisabled)
            .opacity(isDisabled ? 0.5 : 1)
    }
}

// MARK: - Thermostat Hub

/// The physical thermostat's pill: icon, title, state tinted by `hvac_action`, then HVAC mode and fan pickers
/// (web `ThermostatHubPill`).
struct ThermostatHubPill: View {
    var controller: ClimateController
    @State private var picker: HubPicker?
    @Environment(\.dynamicTypeSize) private var typeSize

    enum HubPicker: String, Identifiable {
        case mode, fan
        var id: String { rawValue }
    }

    var body: some View {
        let entity = controller.entity(ClimateConfig.hubEntityId)
        let action = ClimateLogic.hvacAction(entity)
        let tint = ClimateStyle.tint(action: action)
        let state = ClimateLogic.compactState(entity, state: controller.shown(ClimateController.hubModeKey))
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: HassTokens.Spacing.m))
            : AnyLayout(HStackLayout(spacing: HassTokens.Spacing.m))
        layout {
            HStack(spacing: HassTokens.Spacing.m) {
                Image(systemName: ClimateStyle.symbol("mdi:thermostat"))
                    .font(.title2)
                    .foregroundStyle(tint ?? HassTokens.Ink.secondary)
                    .frame(minWidth: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Thermostat Hub")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(HassTokens.Ink.primary)
                    Text(state)
                        .font(.footnote)
                        .foregroundStyle(HassTokens.Ink.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("climate.hub")
            HStack(spacing: HassTokens.Spacing.s) {
                let modes = ClimateLogic.hvacModeOptions(entity)
                HubPickerButton(symbol: "power", label: "Thermostat Hub Mode", value: state, isDisabled: modes.isEmpty) { picker = .mode }
                    .accessibilityIdentifier("climate.hub.mode")
                if !ClimateLogic.fanModeOptions(entity).isEmpty {
                    let fan = ClimateLogic.selectOption(controller.shown(ClimateController.hubFanKey) ?? "")
                    HubPickerButton(symbol: ClimateStyle.symbol("mdi:fan"), label: "Thermostat Hub Fan", value: fan, isDisabled: false) { picker = .fan }
                        .accessibilityIdentifier("climate.hub.fan")
                }
            }
        }
        .padding(HassTokens.Spacing.m)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: HassTokens.Radius.tile, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: HassTokens.Radius.tile, style: .continuous)
                .strokeBorder(tint?.opacity(0.6) ?? .clear, lineWidth: 1.5)
        }
        .accessibilityElement(children: .contain)
        .sheet(item: $picker) { kind in
            switch kind {
            case .mode:
                ClimateOptionPicker(
                    title: "Thermostat Hub Mode",
                    options: ClimateLogic.hvacModeOptions(controller.entity(ClimateConfig.hubEntityId)),
                    selected: controller.shown(ClimateController.hubModeKey),
                    keepsOpen: true,
                    tint: { ClimateStyle.tint(action: $0) }
                ) { controller.setHubMode($0) }
            case .fan:
                ClimateOptionPicker(
                    title: "Thermostat Hub Fan",
                    options: ClimateLogic.fanModeOptions(controller.entity(ClimateConfig.hubEntityId)),
                    selected: controller.shown(ClimateController.hubFanKey),
                    keepsOpen: false
                ) { controller.setHubFan($0) }
            }
        }
    }
}

/// A 44 pt icon button with a disclosure chevron that opens a picker (web `ThermostatSelectButton`).
struct HubPickerButton: View {
    var symbol: String
    var label: String
    var value: String
    var isDisabled: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 2) {
                Image(systemName: symbol).font(.body.weight(.semibold))
                Image(systemName: "chevron.down").font(.caption.weight(.bold))
            }
            .foregroundStyle(HassTokens.Ink.primary)
            .frame(minWidth: 60, minHeight: HassTokens.minTarget)
            .background(RemoteStyle.buttonFill, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(label)
        .accessibilityValue(value)
        .accessibilityHint("Opens choices.")
    }
}

// MARK: - Option picker

/// A sheet of option tiles (web `OptionPickerDialog` with `presentation="sheet"`). With `keepsOpen` it stays
/// up after a choice, so the hub's mode can be changed and checked in one go.
struct ClimateOptionPicker: View {
    var title: String
    var options: [ClimateLogic.Option]
    var selected: String?
    var keepsOpen: Bool
    var tint: (String) -> Color? = { _ in nil }
    var onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    /// Wide enough for "Heat/Cool" with its icon; one column on iPhone.
    @ScaledMetric(relativeTo: .subheadline) private var minTileWidth: CGFloat = 200
    /// Follows the choice at once; the parent's value catches up through the controller.
    @State private var choice: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                DynamicGridLayout(minCellWidth: minTileWidth, maxColumns: 2) {
                    ForEach(options) { option in
                        let isSelected = (choice ?? selected) == option.value
                        RemoteGlassTile(
                            title: option.label,
                            subtitle: option.description,
                            symbol: ClimateStyle.symbol(option.icon ?? "mdi:thermometer-check"),
                            tint: tint(option.value) ?? ClimateStyle.control,
                            isActive: isSelected,
                            isDisabled: false,
                            semantics: .selection(isSelected: isSelected)
                        ) {
                            choice = option.value
                            onSelect(option.value)
                            if !keepsOpen { dismiss() }
                        }
                        .accessibilityIdentifier("climate.picker.\(option.value)")
                    }
                }
                .padding(HassTokens.Spacing.l)
            }
            .climateSheetTitle(title)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
