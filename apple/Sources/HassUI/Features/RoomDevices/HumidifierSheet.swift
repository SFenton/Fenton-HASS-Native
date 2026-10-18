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

/// The humidifier sheet (web `HumidifierModal`): a mist dial with power, and Controls, Schedules and Info tabs in the
/// bottom section bar (direction G, Sheets). Scheduled activities are edited on a pushed page inside the sheet, like
/// the web's in-sheet detail page.
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
            .modalTabBar(HumidifierTab.allCases, label: "Humidifier sections", title: \.title,
                         symbol: ModalTabSymbols.symbol(for:), selection: $tab,
                         identifier: "humidifier.tabs")
            .navigationDestination(item: $editing) { rule in
                HumidifierActivityEditor(schedules: schedules, rule: rule, isNew: !schedules.rules.contains { $0.id == rule.id }) {
                    editing = nil
                }
                .modalChrome()
            }
            .task { await schedules.load() }
        }
    }

    private var tabColumn: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.xl) {
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
            // A grey capsule under the dial (mockup n4 humidifier); the sheet's controls stay the focus.
            Button { controller.togglePower() } label: {
                Label(controller.powerOn ? "Turn Off" : "Turn On", systemImage: "power")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(HassTokens.Ink.primary)
                    .frame(minWidth: 140)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(HassTokens.Ink.primary) // A neutral grey capsule: the accent tint would make it read as the primary action.
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
            if let message = controller.faultMessage { InlineAlert(message) }
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
                SegmentedChoice(label: "Mode", options: HumidifierMode.allCases, title: \.title, selection: controller.mode,
                                identifier: "humidifier.mode") { controller.setMode($0) }
                    .disabled(controller.isBlocked)
            }

            DeviceSection(title: "Mist Output", footnote: "Use the dial for exact levels, or choose a quick preset.") {
                SegmentedChoice(label: "Mist output", options: HumidifierConfig.mistPresets, title: \.title,
                                selection: controller.powerOn ? HumidifierConfig.mistPresets.first(where: { $0.value == controller.mistLevel }) : nil,
                                identifier: "humidifier.mist") { controller.setLevel($0.value) }
                    .disabled(controller.isBlocked || controller.isSleep)
            }

            if controller.mode == .targetHumidity {
                DeviceSection(title: "Target Humidity") {
                    if !controller.targetHumidityValid {
                        InlineAlert("Choose a target before relying on Auto Humidity.", symbol: "humidity")
                    }
                    ThermostatDial(HumidifierDials.target(controller), size: .compact) { targets in
                        if case let .single(value) = targets { controller.setTargetHumidity(value) }
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("humidifier.targetDial")
                    if controller.targetHumidity > 60 {
                        InlineAlert("Targets above 60% can encourage condensation and mold.")
                    } else {
                        Text("40–50% is the recommended comfort range for most homes.")
                            .font(.footnote)
                            .foregroundStyle(HassTokens.Ink.secondary)
                    }
                }
            }

            DeviceSection(title: "Warm Mist") {
                SegmentedChoice(label: "Warm mist", options: HumidifierConfig.warmLevels, title: \.title,
                                selection: HumidifierConfig.warmLevels.first(where: { $0.value == controller.warmLevel }),
                                identifier: "humidifier.warm") { controller.setWarmLevel($0.value) }
                    .disabled(controller.isBlocked || controller.isSleep)
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
                            Label("Cancel Timer · \(HumidifierController.formatSeconds(remaining)) Remaining", systemImage: "xmark")
                                .foregroundStyle(HassTokens.Ink.danger)
                                .frame(minHeight: HassTokens.minTarget)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
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
}

// MARK: - Info

/// Device state and environment readings (web `InfoPanel`).
struct HumidifierInfoTab: View {
    var controller: HumidifierController
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.xl) {
            DeviceSection(title: "Device State") { pills(controller.deviceItems) }
            DeviceSection(title: "Environment") { pills(controller.environmentItems) }
        }
    }

    private func pills(_ items: [HumidifierController.InfoItem]) -> some View {
        // One column at accessibility sizes so values like "Humidifying" never break mid-word.
        DynamicGridLayout(minCellWidth: 150, maxColumns: typeSize.isAccessibilitySize ? 1 : 3) {
            ForEach(items) { DeviceStatusPill(item: $0) }
        }
    }
}

/// A labelled reading with a tone glyph (web `StatusPill`), on the sheet's cell colour (direction G, Layers: Sheets).
struct DeviceStatusPill: View {
    var item: HumidifierController.InfoItem
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // At accessibility sizes the icon sits above the text, giving the value the pill's full width.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: HassTokens.Spacing.s))
            : AnyLayout(HStackLayout(spacing: HassTokens.Spacing.s))
        layout {
            Image(systemName: SymbolMap.symbol(for: item.icon))
                .stateForeground("DeviceStatusPill", Self.color(item.tone))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.caption).foregroundStyle(HassTokens.Ink.secondary)
                Text(item.value).font(.subheadline.weight(.semibold)).foregroundStyle(HassTokens.Ink.primary).monospacedDigit()
            }
            .fixedSize(horizontal: false, vertical: true) // Wrap long values ("Humidifying") instead of truncating.
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(HassTokens.Spacing.m)
        .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: HassTokens.Radius.tile, style: .continuous)
                .fill(HassTokens.Surface.sheetCell)
                .stateColorTransition("DeviceStatusPill", value: item.tone)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title)
        .accessibilityValue(item.value)
        .accessibilityIdentifier("humidifier.info.\(item.title)")
    }

    static func color(_ tone: HumidifierController.InfoItem.Tone) -> Color {
        switch tone {
        case .ok: ColorFamily.occupancy.glyph
        case .active: ColorFamily.water.glyph
        case .warning: HassTokens.Ink.warning
        case .danger: HassTokens.Ink.danger
        case .neutral, .unavailable: HassTokens.Ink.secondary
        }
    }
}
