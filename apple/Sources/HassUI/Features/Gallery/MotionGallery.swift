#if DEBUG
import HassCore
import HassDesign
import SwiftUI

/// Gallery page for the motion rules (`FENTON_GALLERY=motion`; design: `.agents/design/motion-components.md`).
///
/// Every component that has a state colour appears in a card with a **Toggle state** button, and **Toggle all** flips every card
/// at once, so a person can watch each cross-fade (and UI tests can drive them). The toggles change plain state: nothing here wraps
/// them in `withAnimation`, so a component that does not animate its own colours visibly jumps. Launch with
/// `FENTON_SYSTEM_SETTINGS=reduceMotion` to see the Reduce Motion fades.
///
/// Each card's component sits in an element `motion.component.<id>` whose accessibility value is `On` or `Off` and whose frame must
/// not move when the state changes (the rule: only colour animates). `motion.state.<id>` reads the same state as text.
struct MotionGallery: View {
    /// One component with a two-state look.
    struct Case: Identifiable {
        var id: String
        var title: String
        var content: (Bool) -> AnyView
    }

    @State private var onCases: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HassTokens.Spacing.l) {
                Button {
                    if onCases.count == Self.cases.count { onCases = [] } else { onCases = Set(Self.cases.map(\.id)) }
                } label: {
                    Text("Toggle all").frame(minHeight: HassTokens.minTarget)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("motion.toggleAll")
                ForEach(Self.cases) { card($0) }
            }
            .padding(HassTokens.Spacing.l)
        }
        .navigationTitle("Motion")
        .accessibilityIdentifier("motion.scroll")
    }

    private func card(_ item: Case) -> some View {
        let isOn = onCases.contains(item.id)
        return VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
            HStack {
                Text(item.title).font(.headline).foregroundStyle(HassTokens.Ink.primary)
                Spacer()
                Button {
                    if isOn { onCases.remove(item.id) } else { onCases.insert(item.id) }
                } label: {
                    Text("Toggle state").frame(minHeight: HassTokens.minTarget)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Toggle \(item.title)")
                .accessibilityIdentifier("motion.toggle.\(item.id)")
            }
            item.content(isOn)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(item.title)
                .accessibilityValue(isOn ? "On" : "Off")
                .accessibilityIdentifier("motion.component.\(item.id)")
            Text("State: \(isOn ? "On" : "Off")")
                .font(.caption.monospaced())
                .foregroundStyle(HassTokens.Ink.secondary)
                .accessibilityIdentifier("motion.state.\(item.id)")
        }
        .padding(HassTokens.Spacing.m)
        .module(.thin)
    }

    // MARK: Cases

    /// Every component with a state colour that can be built from plain values. (Those that need a controller or a store
    /// are covered by their own gallery pages and the unit tests in `.agents/design/motion-components.md`.)
    static let cases: [Case] = [
        Case(id: "glassTile", title: "GlassTile (heating)") { on in
            AnyView(GlassTile(title: "Thermostat", subtitle: on ? "Heating" : "Idle", symbol: "thermometer", family: on ? .heating : .cooling,
                              isActive: on, kind: .toggle) {})
        },
        Case(id: "glassTileLight", title: "GlassTile (light)") { on in
            AnyView(GlassTile(title: "Lamp", subtitle: on ? "On" : "Off", symbol: "lightbulb", family: .lights, isActive: on,
                              kind: .toggle) {})
        },
        Case(id: "glassTileError", title: "GlassTile (error)") { on in
            AnyView(GlassTile(title: "Front Lock", subtitle: on ? "Jammed" : "Locked", symbol: on ? "lock.open" : "lock", family: .contact,
                              isActive: false, isError: on, kind: .command) {})
        },
        Case(id: "brightnessTile", title: "BrightnessTile") { on in
            AnyView(BrightnessTile(title: "Hall", tint: .yellow, percent: on ? 80 : 0, onPower: { _ in }, onBrightness: { _ in }))
        },
        Case(id: "statusPill", title: "StatusPill") { on in
            AnyView(StatusPill(label: "Filter", value: on ? "Replace" : "Good", symbol: "wind", tone: on ? .warning : .ok))
        },
        Case(id: "statusChip", title: "StatusChipButton") { on in
            AnyView(StatusChipButton(title: "Lights", summary: on ? "3 On" : "All Off", symbol: "lightbulb", family: .lights, isActive: on,
                                     action: {}))
        },
        Case(id: "primaryButton", title: "PrimaryButton") { on in
            AnyView(PrimaryButton("Save") {}.disabled(!on))
        },
        Case(id: "selectableOptionRow", title: "SelectableOptionRow") { on in
            AnyView(SelectableOptionRow(title: "Heat", detail: "Warms the room.", symbol: "flame", tint: .orange, isSelected: on) {})
        },
        Case(id: "filterOptionRow", title: "FilterOptionRow") { on in
            AnyView(FilterOptionRow(title: "Alphabetical", subtitle: "A to Z.", isSelected: on) {})
        },
        Case(id: "floatingActionBar", title: "FloatingActionBar") { on in
            AnyView(FloatingActionBar(actions: [
                FloatingAction(id: "filter", title: "Filter", symbol: "slider.horizontal.3", showsTitle: false, isActive: on) {},
                FloatingAction(id: "add", title: "Add Task", symbol: "plus") {},
            ]))
        },
        Case(id: "choiceGrid", title: "ChoiceGrid") { on in
            AnyView(ChoiceGrid(title: "Mode", options: ["Low", "High"], label: { $0 }, selection: .constant(on ? "High" : "Low"),
                               identifier: "motion.choice"))
        },
        Case(id: "weekdayPicker", title: "WeekdayPicker") { on in
            AnyView(WeekdayPicker(title: "Days", days: .constant(on ? [.monday, .friday] : []), identifier: "motion.weekday"))
        },
        Case(id: "cameraControl", title: "CameraControlButton") { on in
            AnyView(CameraControlButton(title: "Record", symbol: on ? "stop.circle.fill" : "record.circle", isActive: on, tint: .red, pulses: false,
                                        accessibilityLabel: "Record", accessibilityValue: on ? "Recording" : "Not recording", isToggle: true,
                                        identifier: "motion.camera") {})
        },
        Case(id: "dueLabel", title: "DueLabel") { on in
            // The same text both ways: only the colour changes, so the label's own width cannot.
            AnyView(DueLabel(text: "3 days", tone: on ? .overdueLong : .future))
        },
        Case(id: "climateNotice", title: "ClimateNotice") { on in
            AnyView(ClimateNotice(text: on ? "A window is open." : "Everything is closed.", isWarning: on))
        },
        Case(id: "lightingMode", title: "LightingModeButton") { on in
            AnyView(LightingModeButton(mode: on ? "Evening" : "Day",
                                       swatch: on ? [.init(255, 140, 0), .init(120, 0, 160)] : [.init(255, 255, 255), .init(120, 200, 255)],
                                       action: {}))
        },
        Case(id: "deviceStatusPill", title: "DeviceStatusPill") { on in
            AnyView(DeviceStatusPill(item: .init(title: "Water", icon: "mdi:water", value: on ? "Low" : "Full", tone: on ? .warning : .ok)))
        },
        Case(id: "alarmMode", title: "AlarmModeButton") { on in
            AnyView(AlarmModeButton(mode: SecurityConfig.modeButtons[1], isSelected: on, isUnavailable: false) {}
                .frame(width: 96))
        },
        Case(id: "dayPicker", title: "DayPicker (sprinklers)") { on in
            AnyView(DayPicker(days: .constant(on ? [1, 3, 5] : [])))
        },
        Case(id: "sprinklerRow", title: "SprinklerRow") { on in
            AnyView(SprinklerRow(symbol: "sprinkler.and.droplets", isActive: on, title: "Front Lawn", lines: ["Front yard"]))
        },
        Case(id: "sprinklerControllerRow", title: "ModuleRow (controller)") { on in
            AnyView(ModuleList { SprinklerControllerRow(title: "Controller", subtitle: on ? "Watering" : "Idle", isWatering: on) {} })
        },
        Case(id: "vacationChecklistRow", title: "VacationChecklistRow") { on in
            AnyView(VacationChecklistRow(title: "Lock the doors", isChecked: on, isUnavailable: false) {})
        },
        Case(id: "vacuumStatusChip", title: "VacuumStatusChip") { on in
            AnyView(VacuumStatusChip(symbol: "battery.25", tint: on ? .red : .green, label: "Battery", value: on ? "12%" : "88%"))
        },
    ]
}
#endif
