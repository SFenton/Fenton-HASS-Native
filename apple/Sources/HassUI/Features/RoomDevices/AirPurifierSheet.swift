import HassCore
import HassDesign
import SwiftUI

/// The air purifier sheet (web `AirQualityModalContent.tsx`): fan mode, then Auto's sub-mode or Manual's speed.
public struct AirPurifierSheet: View {
    @State private var controller: AirPurifierController

    /// Creates the sheet.
    public init(config: AirPurifierConfig, store: EntityStore, caller: any HassServiceCalling) {
        _controller = State(initialValue: AirPurifierController(config: config, store: store, caller: caller))
    }

    /// Creates the sheet on the app's connection.
    public init(config: AirPurifierConfig, connection: HassConnection) {
        self.init(config: config, store: connection.store, caller: connection)
    }

    init(controller: AirPurifierController) {
        _controller = State(initialValue: controller)
    }

    public var body: some View {
        RoomDeviceSheetChrome(title: "\(controller.config.roomTitle) Air Quality", subtitle: controller.summary,
                              identifier: "device.sheet.purifier") {
            ScrollView {
                AirPurifierControls(controller: controller)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                    .padding(HassTokens.Spacing.l)
            }
        }
    }
}

/// The purifier's sections.
struct AirPurifierControls: View {
    var controller: AirPurifierController

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.xl) {
            section("Fan Modes", options: AirPurifierController.fanModes, selected: controller.mode,
                    disabled: controller.modeUnavailable, id: "mode", select: controller.selectMode)
            if controller.showsAutoModes {
                section("Auto Modes", options: AirPurifierController.autoModes, selected: controller.autoMode,
                        disabled: controller.autoModeUnavailable, id: "auto", select: controller.selectAutoMode)
            }
            if controller.showsSpeeds {
                section("Manual Modes", options: AirPurifierController.speeds, selected: controller.percentage,
                        disabled: controller.fanUnavailable, id: "speed", select: controller.selectSpeed)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(controller.config.roomTitle) air purifier controls")
    }

    private func section(_ title: String, options: [AirPurifierController.Option], selected: String?, disabled: Bool,
                         id: String, select: @escaping (AirPurifierController.Option) -> Void) -> some View {
        DeviceSection(title: title) {
            DeviceTileGrid(maxColumns: options.count) {
                ForEach(options) { option in
                    let isSelected = selected == option.value
                    RemoteGlassTile(title: option.title, symbol: SymbolMap.symbol(for: option.icon), tint: RoomDeviceStyle.mode,
                                    isActive: isSelected && !disabled, isDisabled: disabled,
                                    semantics: .selection(isSelected: isSelected)) {
                        select(option)
                    }
                    .accessibilityIdentifier("purifier.\(id).\(option.title)")
                }
            }
        }
    }
}

/// The grill sheet (web `GrillModalContent.tsx`): the grill's state and its probe, pellet and mode cards.
public struct GrillSheet: View {
    @State private var controller: GrillController

    /// Creates the sheet.
    public init(config: GrillConfig = .bearGrills, store: EntityStore, caller: any HassServiceCalling) {
        _controller = State(initialValue: GrillController(config: config, store: store, caller: caller))
    }

    /// Creates the sheet on the app's connection.
    public init(config: GrillConfig = .bearGrills, connection: HassConnection) {
        self.init(config: config, store: connection.store, caller: connection)
    }

    init(controller: GrillController) {
        _controller = State(initialValue: controller)
    }

    public var body: some View {
        RoomDeviceSheetChrome(title: "\(controller.config.roomTitle): \(controller.config.title)", subtitle: controller.stateText, identifier: "device.sheet.grill") {
            ScrollView {
                GrillControls(controller: controller)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                    .padding(HassTokens.Spacing.l)
            }
        }
    }
}

/// The grill's header and cards.
struct GrillControls: View {
    var controller: GrillController

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.xl) {
            HStack(spacing: HassTokens.Spacing.m) {
                Image(systemName: "flame.fill")
                    .font(.title2)
                    .foregroundStyle(controller.isOff ? HassTokens.Ink.secondary : RoomDeviceStyle.grill)
                    .frame(width: HassTokens.minTarget, height: HassTokens.minTarget)
                    .background(.regularMaterial, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(controller.config.title).font(.headline).foregroundStyle(HassTokens.Ink.primary)
                    Text(controller.stateText).font(.subheadline).foregroundStyle(HassTokens.Ink.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("grill.header")

            DeviceTileGrid(maxColumns: 2) {
                ForEach(controller.config.details) { detail in
                    let display = controller.display(detail)
                    RemoteGlassTile(title: detail.title, subtitle: display.value, symbol: SymbolMap.symbol(for: detail.icon),
                                    tint: RoomDeviceStyle.grill, isActive: display.isActive, isDisabled: display.isUnavailable,
                                    semantics: detail.isSwitch ? .toggle(isOn: display.isActive) : .state) {
                        controller.toggle(detail)
                    }
                    .accessibilityIdentifier("grill.\(detail.title)")
                }
            }
        }
    }
}
