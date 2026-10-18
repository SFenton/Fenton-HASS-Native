@testable import HassCore
@testable import HassDesign
@testable import HassUI
import HassTestSupport
import SwiftUI
import Testing

/// Each screen-level component in `.agents/design/motion-components.md` that colours from state registers a state colour
/// animation with ``MotionAudit`` when it renders, so dropping the helper fails here. The shared HassDesign components are in
/// `ComponentMotionTests`; the Motion gallery drives all of them on screen.
@MainActor
struct MotionComponentsTests {
    private func audit<V: View>(_ view: @autoclosure () -> V, width: CGFloat = 402) -> Set<String> {
        MotionAudit.capture { _ = ImageRenderer(content: view().frame(width: width)).cgImage }
    }

    @Test func statusChipUsesTheStateToken() {
        let looks: [(ColorFamily?, Bool)] = [(.lights, true), (.contact, false), (nil, false)]
        for (family, active) in looks {
            let chip = StatusChipButton(title: "Lights", summary: "3 On", symbol: "lightbulb", family: family, isActive: active, action: {})
            #expect(audit(chip).contains("StatusChip"))
        }
        let tinted = StatusChipButton(title: "Air", summary: "Good", symbol: "wind", family: nil, isActive: false, tint: .contactOpenAway, action: nil)
        #expect(audit(tinted).contains("StatusChip"))
        #expect(MotionTokens.state == .easeInOut(duration: 0.6))
    }

    @Test func bedroomPickersAnimateSelection() {
        #expect(audit(ChoiceGrid(title: "Mode", options: ["A", "B"], label: { $0 }, selection: .constant("A"), identifier: "c")).contains("ChoiceGrid"))
        #expect(audit(WeekdayPicker(title: "Days", days: .constant([.monday]), identifier: "w")).contains("WeekdayPicker"))
    }

    @Test func cameraControlAnimatesItsActiveTint() {
        for active in [false, true] {
            let button = CameraControlButton(title: "Record", symbol: "record.circle", isActive: active, tint: .red, pulses: false,
                                             accessibilityLabel: "Record", accessibilityValue: "", identifier: "r") {}
            #expect(audit(button).contains("CameraControlButton"))
        }
    }

    @Test func choreLabelsAnimateTheirInk() {
        for tone in [TodoItem.DueTone.future, .overdueHours, .overdueLong] {
            #expect(audit(DueLabel(text: "soon", tone: tone)).contains("DueLabel"))
        }
        let open = TodoItem(uid: "1", summary: "Task")
        let done = TodoItem(uid: "2", summary: "Done", status: .completed)
        for item in [open, done] {
            #expect(audit(VStack { TodoItemRow(item: item, now: .now, onToggle: {}) }).contains("TodoItemRow"))
        }
    }

    @Test func climateNoticeAnimatesInkAndGround() {
        #expect(audit(ClimateNotice(text: "Open window", isWarning: true)).contains("ClimateNotice"))
        #expect(audit(ClimateNotice(text: "Info")).contains("ClimateNotice"))
    }

    @Test func customLightsAnimateTheirSwatches() {
        let swatch = [CustomLightsConfig.RGB(255, 0, 0), CustomLightsConfig.RGB(0, 0, 255)]
        #expect(audit(LightingModeButton(mode: "Party", swatch: swatch, action: {})).contains("LightingModeButton"))
        let light = CustomLightsConfig.lights[0]
        #expect(audit(OtherLightSwatch(light: light, rgb: CustomLightsConfig.RGB(255, 100, 0), apply: { _ in })).contains("OtherLightSwatch"))
        #expect(audit(OtherLightSwatch(light: light, rgb: nil, apply: { _ in })).contains("OtherLightSwatch"))
    }

    @Test func weatherBarsAnimateWhenAValueArrives() {
        let chart = WeatherBarChart(values: [10, nil, 40], domain: 100, axisLabels: ("100%", "50%", "0%"), hourLabels: ["1", "2", "3"], tint: .blue)
        #expect(audit(chart, width: 300).contains("WeatherBarChart"))
    }

    @Test func deviceControlsAnimateTheirColours() {
        let item = HumidifierController.InfoItem(title: "Water", icon: "mdi:water", value: "Low", tone: .warning)
        #expect(audit(DeviceStatusPill(item: item)).contains("DeviceStatusPill"))
        let grill = GrillControls(controller: GrillController(store: EntityStore(), caller: RecordingCaller()))
        #expect(audit(grill).contains("GrillControls"))
    }

    @Test func alarmPanelAndModeButtonsAnimate() {
        let modes = SecurityConfig.modeButtons
        for (selected, onAlarm) in [(false, false), (true, false), (false, true)] {
            #expect(audit(AlarmModeButton(mode: modes[1], isSelected: selected, isUnavailable: false, onAlarm: onAlarm) {}, width: 90)
                .contains("AlarmModeButton"))
        }
        #expect(AlarmModeLook(isSelected: true, onAlarm: false) != AlarmModeLook(isSelected: false, onAlarm: false))
        for scenario in [SecurityFixtures.Scenario.standard, .triggered, .unavailable] {
            let panel = AlarmPanel(caller: RecordingCaller()).environment(SecurityFixtures.store(scenario))
            #expect(audit(panel, width: 370).contains("AlarmPanel"))
            #expect(audit(panel.environment(\.tileSurface, .sheet), width: 370).contains("AlarmPanel"))
        }
    }

    @Test func settingsAndSprinklersAnimateSelection() {
        #expect(audit(AppIconChoiceButton(choice: AppIconChoice.allCases[0], isSelected: true, action: {})).contains("AppIconChoiceButton"))
        #expect(audit(DayPicker(days: .constant([1, 3]))).contains("DayPicker"))
        #expect(audit(SprinklerRow(symbol: "sprinkler.and.droplets", isActive: true, title: "Lawn", lines: ["Watering"])).contains("SprinklerRow"))
        #expect(audit(ModuleList { SprinklerControllerRow(title: "Controller", subtitle: "Idle", isWatering: true) {} }).contains("ModuleRow"))
    }

    @Test func vacationAndVacuumComponentsAnimate() {
        #expect(audit(VacationChecklistRow(title: "Lock up", isChecked: true, isUnavailable: false) {}).contains("VacationChecklistRow"))
        #expect(audit(VacuumStatusChip(symbol: "battery.25", tint: .red, label: "Battery", value: "12%")).contains("VacuumStatusChip"))
    }
}
