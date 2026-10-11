import HassCore
import HassDesign
import SwiftUI

/// The humidifier sheet's tabs (web `HUMIDIFIER_MODAL_TABS`).
public enum HumidifierTab: String, CaseIterable, Identifiable, Sendable {
    case controls, schedules, info
    public var id: String { rawValue }

    var title: String {
        switch self {
        case .controls: "Controls"
        case .schedules: "Schedules"
        case .info: "Info"
        }
    }
}

/// When the humidifier sheet splits: the hero dial in a leading column, the tab in a trailing one.
enum HumidifierLayout {
    /// The narrowest sheet that fits the dial beside a tab.
    static let minimumTwoColumnWidth: CGFloat = 640

    /// Only where the window may split (landscape, regular width; `SplitPolicy`) and the sheet is wide enough.
    static func usesTwoColumns(window: CGSize, isRegularWidth: Bool, container: CGSize) -> Bool {
        SplitPolicy.allowsSplit(size: window, isRegularWidth: isRegularWidth) && container.width >= minimumTwoColumnWidth
    }
}

/// The humidifier sheet (web `HumidifierModal`): a mist dial with power, and Controls, Schedules and Info tabs.
/// Scheduled activities are edited on a pushed page inside the sheet, like the web's in-sheet detail page.
public struct HumidifierSheet: View {
    @State private var controller: HumidifierController
    @State private var schedules: HumidifierScheduleController
    @State private var tab: HumidifierTab
    @State private var window = WindowMetrics()
    @State private var editing: HumidifierScheduleRule?

    /// Creates the sheet.
    public init(config: HumidifierConfig, store: EntityStore, caller: any HassServiceCalling, storage: any HassScheduleStoring,
                initialTab: HumidifierTab = .controls) {
        self.init(controller: HumidifierController(config: config, store: store, caller: caller),
                  schedules: HumidifierScheduleController(config: config, store: store, caller: caller, storage: storage),
                  initialTab: initialTab)
    }

    /// Creates the sheet on the app's connection.
    public init(config: HumidifierConfig, connection: HassConnection, initialTab: HumidifierTab = .controls) {
        self.init(config: config, store: connection.store, caller: connection, storage: connection, initialTab: initialTab)
    }

    /// Creates the sheet on existing controllers; `window` stands in for the hosting window in hosted tests.
    init(controller: HumidifierController, schedules: HumidifierScheduleController, initialTab: HumidifierTab,
         window: WindowMetrics? = nil) {
        _controller = State(initialValue: controller)
        _schedules = State(initialValue: schedules)
        _tab = State(initialValue: initialTab)
        _window = State(initialValue: window ?? WindowMetrics())
    }

    public var body: some View {
        RoomDeviceSheetChrome(title: controller.config.title, subtitle: controller.subtitle, identifier: "device.sheet.humidifier") {
            GeometryReader { proxy in
                let twoColumns = HumidifierLayout.usesTwoColumns(window: window.size ?? proxy.size,
                                                                 isRegularWidth: window.isRegularWidth, container: proxy.size)
                Group {
                    if twoColumns {
                        HStack(alignment: .top, spacing: 0) {
                            ScrollView { HumidifierHero(controller: controller).padding(HassTokens.Spacing.l) }
                                .frame(width: proxy.size.width / 2)
                            ScrollView { tabColumn.padding(HassTokens.Spacing.l) }
                                .frame(width: proxy.size.width / 2)
                        }
                    } else {
                        ScrollView {
                            VStack(spacing: HassTokens.Spacing.xl) {
                                HumidifierHero(controller: controller)
                                tabColumn
                            }
                            .frame(maxWidth: 640)
                            .frame(maxWidth: .infinity)
                            .padding(HassTokens.Spacing.l)
                        }
                    }
                }
                .accessibilityIdentifier(twoColumns ? "humidifier.layout.twoColumn" : "humidifier.layout.singleColumn")
            }
            .background { WindowMetricsReader(metrics: $window) }
            .navigationDestination(item: $editing) { rule in
                HumidifierActivityEditor(schedules: schedules, rule: rule, isNew: !schedules.rules.contains { $0.id == rule.id }) {
                    editing = nil
                }
            }
            .task { await schedules.load() }
        }
    }

    private var tabColumn: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.xl) {
            Picker("Humidifier sections", selection: $tab) {
                ForEach(HumidifierTab.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("humidifier.tabs")
            switch tab {
            case .controls: HumidifierControlsTab(controller: controller)
            case .schedules:
                HumidifierSchedulesTab(schedules: schedules) { rule in
                    schedules.clearError()
                    editing = rule
                } onAdd: {
                    schedules.clearError()
                    editing = HumidifierScheduleRule.new(mode: controller.mode, mistLevel: controller.mistLevel, targetHumidity: controller.targetHumidity,
                                   warmLevel: controller.warmLevel, display: controller.displayOn)
                }
            case .info: HumidifierInfoTab(controller: controller)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Hero

/// The mist dial, power button, hint, fault banner and the humidity and temperature readings.
struct HumidifierHero: View {
    var controller: HumidifierController

    var body: some View {
        VStack(spacing: HassTokens.Spacing.l) {
            ThermostatDial(HumidifierDials.mist(controller), size: .modal) { targets in
                if case let .single(value) = targets { controller.setLevel(Int(value.rounded())) }
            }
            .accessibilityIdentifier("humidifier.mistDial")
            Button { controller.togglePower() } label: {
                Label(controller.powerOn ? "Turn Off" : "Turn On", systemImage: "power")
                    .frame(minWidth: 140)
            }
            .buttonStyle(.borderedProminent)
            .tint(controller.powerOn ? RoomDeviceStyle.powerOff : RoomDeviceStyle.powerOn)
            .controlSize(.large)
            .disabled(!controller.canTogglePower)
            .accessibilityIdentifier("humidifier.power")
            if let hint = controller.hint {
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(HassTokens.Ink.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let message = controller.faultMessage { DeviceAlert(text: message) }
            DynamicGridLayout(minCellWidth: 150, maxColumns: 2) {
                DeviceStatusPill(item: .init(title: "Current Humidity", icon: "mdi:water-percent", value: controller.humidityText, tone: .neutral))
                DeviceStatusPill(item: .init(title: "Temperature", icon: "mdi:thermometer", value: controller.temperatureText, tone: .neutral))
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Controls

/// Mode, mist presets, target humidity, warm mist, device timer and display (web `ControlsPanel`).
struct HumidifierControlsTab: View {
    var controller: HumidifierController

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.xl) {
            DeviceSection(title: "Mode") {
                DeviceTileGrid(maxColumns: 3) {
                    ForEach(HumidifierMode.allCases, id: \.self) { mode in
                        choice(mode.title, icon: mode.icon, selected: controller.mode == mode, disabled: controller.isBlocked,
                               id: "humidifier.mode.\(mode.title)") { controller.setMode(mode) }
                    }
                }
            }

            DeviceSection(title: "Mist Output", footnote: "Use the dial for exact levels, or choose a quick preset.") {
                DeviceTileGrid {
                    ForEach(HumidifierConfig.mistPresets) { preset in
                        choice(preset.title, subtitle: "Level \(preset.value)", icon: preset.icon,
                               selected: controller.powerOn && controller.mistLevel == preset.value,
                               disabled: controller.isBlocked || controller.isSleep,
                               id: "humidifier.mist.\(preset.title)") { controller.setLevel(preset.value) }
                    }
                }
            }

            if controller.mode == .targetHumidity {
                DeviceSection(title: "Target Humidity") {
                    if !controller.targetHumidityValid {
                        DeviceAlert(text: "Choose a target before relying on Auto Humidity.", symbol: "humidity")
                    }
                    ThermostatDial(HumidifierDials.target(controller), size: .compact) { targets in
                        if case let .single(value) = targets { controller.setTargetHumidity(value) }
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("humidifier.targetDial")
                    if controller.targetHumidity > 60 {
                        DeviceAlert(text: "Targets above 60% can encourage condensation and mold.")
                    } else {
                        Text("40–50% is the recommended comfort range for most homes.")
                            .font(.footnote)
                            .foregroundStyle(HassTokens.Ink.secondary)
                    }
                }
            }

            DeviceSection(title: "Warm Mist") {
                DeviceTileGrid {
                    ForEach(HumidifierConfig.warmLevels) { level in
                        choice(level.title, icon: level.icon, selected: controller.warmLevel == level.value,
                               disabled: controller.isBlocked || controller.isSleep,
                               id: "humidifier.warm.\(level.title)") { controller.setWarmLevel(level.value) }
                    }
                }
            }

            if controller.powerOn {
                DeviceSection(title: "Device Timer", footnote: "This one-shot timer turns the humidifier off. Recurring activities live in Schedules.") {
                    Stepper(value: Binding(get: { controller.timerMinutes }, set: { controller.setTimerMinutes($0) }),
                            in: HumidifierController.timerRange, step: HumidifierController.timerStep) {
                        LabeledContent("Turn Off In", value: HumidifierController.formatMinutes(controller.timerMinutes))
                            .foregroundStyle(HassTokens.Ink.primary)
                    }
                    .disabled(controller.isBlocked)
                    .accessibilityIdentifier("humidifier.timer")
                    if let remaining = controller.timerRemaining, remaining > 0 {
                        Button(role: .destructive) { controller.setTimerMinutes(0) } label: {
                            Label("Cancel timer · \(HumidifierController.formatSeconds(remaining)) remaining", systemImage: "xmark")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("humidifier.cancelTimer")
                    }
                }

                DeviceSection(title: "Display") {
                    Toggle(isOn: Binding(get: { controller.displayOn }, set: { controller.setDisplay($0) })) {
                        Label("Display", systemImage: "display")
                    }
                    .foregroundStyle(HassTokens.Ink.primary)
                    .frame(minHeight: HassTokens.minTarget)
                    .disabled(controller.isBlocked || controller.isSleep)
                    .accessibilityIdentifier("humidifier.display")
                }
            }
        }
    }

    private func choice(_ title: String, subtitle: String? = nil, icon: String, selected: Bool, disabled: Bool, id: String,
                        action: @escaping () -> Void) -> some View {
        RemoteGlassTile(title: title, subtitle: subtitle, symbol: SymbolMap.symbol(for: icon), tint: RoomDeviceStyle.mode,
                        isActive: selected && !disabled, isDisabled: disabled, semantics: .selection(isSelected: selected),
                        action: action)
            .accessibilityIdentifier(id)
    }
}

// MARK: - Info

/// Device state and environment readings (web `InfoPanel`).
struct HumidifierInfoTab: View {
    var controller: HumidifierController

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.xl) {
            DeviceSection(title: "Device State") { pills(controller.deviceItems) }
            DeviceSection(title: "Environment") { pills(controller.environmentItems) }
        }
    }

    private func pills(_ items: [HumidifierController.InfoItem]) -> some View {
        DynamicGridLayout(minCellWidth: 150, maxColumns: 3) {
            ForEach(items) { DeviceStatusPill(item: $0) }
        }
    }
}

/// A labelled reading with a tone dot (web `StatusPill`).
struct DeviceStatusPill: View {
    var item: HumidifierController.InfoItem

    var body: some View {
        HStack(spacing: HassTokens.Spacing.s) {
            Image(systemName: SymbolMap.symbol(for: item.icon))
                .foregroundStyle(Self.color(item.tone))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.caption).foregroundStyle(HassTokens.Ink.secondary)
                Text(item.value).font(.subheadline.weight(.semibold)).foregroundStyle(HassTokens.Ink.primary).monospacedDigit()
            }
            .fixedSize(horizontal: false, vertical: true) // Wrap long values ("Humidifying") instead of truncating.
            Spacer(minLength: 0)
        }
        .padding(HassTokens.Spacing.m)
        .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: HassTokens.Radius.chip, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title)
        .accessibilityValue(item.value)
        .accessibilityIdentifier("humidifier.info.\(item.title)")
    }

    static func color(_ tone: HumidifierController.InfoItem.Tone) -> Color {
        switch tone {
        case .ok: .green
        case .active: Color(RoomDeviceStyle.humidifierTint)
        case .warning: .orange
        case .danger: .red
        case .neutral, .unavailable: HassTokens.Ink.secondary
        }
    }
}
