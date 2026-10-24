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

/// The purifier's sections: each a short single choice (direction G, Controls: Choosing one option).
struct AirPurifierControls: View {
    var controller: AirPurifierController

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.xl) {
            section("Fan Mode", options: AirPurifierController.fanModes, selected: controller.mode,
                    disabled: controller.modeUnavailable, id: "mode", select: controller.selectMode)
            if controller.showsAutoModes {
                section("Auto Mode", options: AirPurifierController.autoModes, selected: controller.autoMode,
                        disabled: controller.autoModeUnavailable, id: "auto", select: controller.selectAutoMode)
            }
            if controller.showsSpeeds {
                section("Fan Speed", options: AirPurifierController.speeds, selected: controller.percentage,
                        disabled: controller.fanUnavailable, id: "speed", select: controller.selectSpeed)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(controller.config.roomTitle) air purifier controls")
    }

    private func section(_ title: String, options: [AirPurifierController.Option], selected: String?, disabled: Bool,
                         id: String, select: @escaping (AirPurifierController.Option) -> Void) -> some View {
        DeviceSection(title: title) {
            SegmentedChoice(label: title, options: options, title: \.title,
                            selection: options.first(where: { $0.value == selected }), identifier: "purifier.\(id)", select: select)
                .disabled(disabled)
        }
    }
}
