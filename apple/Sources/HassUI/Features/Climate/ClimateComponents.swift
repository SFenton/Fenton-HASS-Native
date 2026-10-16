import HassCore
import HassDesign
import SwiftUI

// MARK: - Style

/// Colours local to the Climate page and sheet.
enum ClimateStyle {
    /// Heating: the heating family's glyph (the dial's heat `#CD5401`, lifted for a glyph on dark).
    static let heat = ColorFamily.heating.glyph
    /// Cooling: the cooling family's glyph (the dial's cool `#2C8E98`, lifted).
    static let cool = ColorFamily.cooling.glyph

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

// MARK: - Page notice

/// A notice on the wallpaper (web `Notice` / the integration warning; mockup n3's away and warning cards): a glyph and
/// the text on a module, read as one element. A warning sits on the dense module with an orange glyph.
struct ClimateNotice: View {
    var text: String
    var symbol = "info.circle"
    var isWarning = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: HassTokens.Spacing.m) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(isWarning ? HassTokens.Ink.warning : HassTokens.Ink.action)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, HassTokens.Spacing.m + 2)
        .padding(.horizontal, HassTokens.Spacing.l)
        .module(isWarning ? .dense : .thin)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Thermostat Hub

/// The physical thermostat's rows (web `ThermostatHubPill`; mockup n3): the hub with its state, glyph tinted by
/// `hvac_action`, and its mode as a pop-up menu, then the fan's pop-up menu when the hub reports fan modes.
struct ClimateHubList: View {
    var controller: ClimateController

    var body: some View {
        let entity = controller.entity(ClimateConfig.hubEntityId)
        let action = ClimateLogic.hvacAction(entity)
        let state = ClimateLogic.compactState(entity, state: controller.shown(ClimateController.hubModeKey))
        let fans = ClimateLogic.fanModeOptions(entity)
        ModuleList {
            ModuleRow("Thermostat Hub", subtitle: state, symbol: ClimateStyle.symbol("mdi:thermostat"),
                      glyph: ClimateStyle.tint(action: action)) {
                HubPicker(label: "Thermostat Hub Mode", value: state, options: ClimateLogic.hvacModeOptions(entity),
                          selected: controller.shown(ClimateController.hubModeKey)) { controller.setHubMode($0) }
                    .accessibilityIdentifier("climate.hub.mode")
            }
            if !fans.isEmpty {
                let fan = ClimateLogic.selectOption(controller.shown(ClimateController.hubFanKey) ?? "")
                ModuleRow("Fan", symbol: ClimateStyle.symbol("mdi:fan")) {
                    HubPicker(label: "Thermostat Hub Fan", value: fan, options: fans,
                              selected: controller.shown(ClimateController.hubFanKey)) { controller.setHubFan($0) }
                        .accessibilityIdentifier("climate.hub.fan")
                }
            }
        }
    }
}

/// A pop-up menu of choices, the current one checked (direction G, Controls: "Thermostat Hub mode and Fan are pop-up
/// menus"; web `ThermostatSelectButton`). HIG: Pop-up buttons.
///
/// The picker sits in a `Menu` whose label is the current value and an up-down chevron: a bare `Picker(.menu)` keeps
/// its own UIKit hit area, which a frame outside it doesn't grow to 44 pt.
struct HubPicker: View {
    var label: String
    /// The current choice as shown, read as the control's value.
    var value: String
    var options: [ClimateLogic.Option]
    var selected: String?
    var onSelect: (String) -> Void

    var body: some View {
        Menu {
            Picker(label, selection: Binding(get: { selected }, set: { if let value = $0 { onSelect(value) } })) {
                ForEach(options) { option in
                    Label(option.label, systemImage: ClimateStyle.symbol(option.icon ?? "mdi:thermometer-check"))
                        .tag(Optional(option.value))
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 4) {
                Text(value)
                    .font(.body)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(HassTokens.Ink.action)
            .frame(minWidth: HassTokens.minTarget, minHeight: HassTokens.minTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(options.isEmpty)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}
