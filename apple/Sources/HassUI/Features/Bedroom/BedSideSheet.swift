import HassCore
import HassDesign
import SwiftUI

/// One bed side's sheet (pattern: `.agents/patterns/bedroom-devices.md`; web `EightSleepBedModal` in SleepyPod
/// climate mode).
///
/// The hero (level dial, power, hint and any ringing alarm) sits above the tabs, or beside them where a split is
/// allowed (iPad and unfolded iPhone Duo in landscape). Alarm day pages and the alarm editor push inside the sheet.
public struct BedSideSheet: View {
    /// A sheet tab (web `SLEEPYPOD_MODAL_TABS`).
    public enum Tab: String, CaseIterable, Identifiable, Sendable {
        case temperature, specialModes = "special-modes", alarms, status
        public var id: String { rawValue }
        var title: String {
            switch self {
            case .temperature: "Temperature"
            case .specialModes: "Special Modes"
            case .alarms: "Alarms"
            case .status: "Status"
            }
        }
    }

    /// A pushed page.
    enum Route: Hashable {
        case day(Weekday)
        case add(Weekday?)
        case edit(String)
    }

    let devices: BedroomDevices
    let side: BedSide
    @State private var tab: Tab
    @State private var path: [Route] = []
    @State private var window = WindowMetrics()
    @State private var confirmingPowerOff = false
    @Environment(\.dismiss) private var dismiss

    /// Creates the sheet.
    /// - Parameters:
    ///   - devices: The room's controllers.
    ///   - side: Which side.
    ///   - initialTab: The tab shown first (the wake-light sheet opens Alarms).
    public init(devices: BedroomDevices, side: BedSide, initialTab: Tab = .temperature) {
        self.init(devices: devices, side: side, initialTab: initialTab, window: nil)
    }

    /// `window` stands in for the hosting window in hosted tests.
    init(devices: BedroomDevices, side: BedSide, initialTab: Tab, window: WindowMetrics?) {
        self.devices = devices
        self.side = side
        _tab = State(initialValue: initialTab)
        _window = State(initialValue: window ?? WindowMetrics())
    }

    private var controller: BedSideController { devices.bed(side) }

    public var body: some View {
        NavigationStack(path: $path) {
            GeometryReader { proxy in
                let twoColumns = MediaRemoteLayout.usesTwoColumns(
                    window: window.size ?? proxy.size, isRegularWidth: window.isRegularWidth, container: proxy.size)
                Group {
                    if twoColumns {
                        HStack(alignment: .top, spacing: 0) {
                            ScrollView { hero.padding(HassTokens.Spacing.l) }
                                .frame(width: proxy.size.width / 2)
                            ScrollView { tabs.padding(HassTokens.Spacing.l) }
                                .frame(width: proxy.size.width / 2)
                        }
                    } else {
                        ScrollView {
                            VStack(spacing: HassTokens.Spacing.xl) {
                                hero
                                tabs
                            }
                            .frame(maxWidth: 640)
                            .frame(maxWidth: .infinity)
                            .padding(HassTokens.Spacing.l)
                        }
                    }
                }
                .accessibilityIdentifier(twoColumns ? "bed.layout.twoColumn" : "bed.layout.singleColumn")
            }
            .background { WindowMetricsReader(metrics: $window) }
            .navigationTitle(controller.title)
            .inlineNavigationTitle()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case let .day(day): BedAlarmDayPage(devices: devices, side: side, day: day, path: $path)
                case let .add(day): BedAlarmEditor(devices: devices, side: side, alarmId: nil, lockedDay: day) { path.removeAll() }
                case let .edit(id): BedAlarmEditor(devices: devices, side: side, alarmId: id, lockedDay: nil) { path.removeAll() }
                }
            }
        }
        .sheet(isPresented: Binding(get: { controller.scopeRequest != nil }, set: { if !$0 { controller.dismissScope() } })) {
            BedTemperatureScopeSheet(controller: controller)
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: HassTokens.Spacing.l) {
            Text(controller.subtitle)
                .font(.subheadline)
                .foregroundStyle(HassTokens.Ink.secondary)
                .accessibilityIdentifier("bed.subtitle")
            if !controller.sideAvailable {
                BedroomNotice(message: "Bed controls are unavailable. No changes can be made until the active bed connection recovers.")
            }
            if let notice = controller.scope.notice {
                BedroomNotice(title: notice.title, message: notice.message, tone: controller.scope.controlsWholeBed ? .success : .info)
                    .accessibilityIdentifier("bed.soloTrip")
            }
            if let error = controller.commandError {
                BedroomNotice(message: error, tone: .error)
            }
            ThermostatDial(BedDial.configuration(controller), size: .modal) { targets in
                if case let .single(value) = targets { controller.setTarget(value) }
            }
            .accessibilityIdentifier("bed.dial")
            // The traveler's side is read-only: the hint below says so, and a disabled button would repeat it at 1.5:1.
            if controller.scope.interactive { powerButton }
            Text(controller.hint)
                .font(.footnote)
                .foregroundStyle(HassTokens.Ink.secondary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("bed.hint")
            ActiveBedAlarmSection(controller: controller)
        }
        .frame(maxWidth: .infinity)
    }

    private var powerButton: some View {
        Button {
            if controller.isOn { confirmingPowerOff = true } else { controller.setPower(on: true) }
        } label: {
            Label(controller.powerTitle, systemImage: "power")
                .frame(minWidth: 160, minHeight: HassTokens.minTarget)
        }
        .buttonStyle(.borderedProminent)
        .tint(controller.isOn ? BedroomStyle.tint(action: controller.action) : BedroomStyle.off)
        .disabled(!controller.canTogglePower)
        .accessibilityIdentifier("bed.power")
        .confirmationDialog("Turn off \(controller.config.title)?", isPresented: $confirmingPowerOff, titleVisibility: .visible) {
            Button("Turn Off", role: .destructive) { controller.setPower(on: false) }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Tabs

    private var tabs: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.xl) {
            BedroomTabPicker(label: "\(controller.config.title) sections", tabs: Tab.allCases, title: \.title,
                             selection: $tab, identifier: "bed.tabs")
            switch tab {
            case .temperature: BedScheduleTab(controller: controller)
            case .specialModes: BedSpecialModesTab(controller: controller)
            case .alarms: BedAlarmsTab(controller: controller, path: $path)
            case .status: BedStatusTab(controller: controller)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Dial mapping

/// Maps a bed side onto ``ThermostatDial`` with the signed level scale (web `EightSleepThermostatHero`).
enum BedDial {
    @MainActor
    static func configuration(_ controller: BedSideController) -> ThermostatDialConfiguration {
        let range = controller.targetRange
        let target = controller.displayedTarget
        var configuration = ThermostatDialConfiguration(
            title: controller.config.title,
            min: range.lowerBound, max: range.upperBound, step: controller.targetStep,
            current: controller.currentLevel,
            targets: target.map { .single($0) },
            action: controller.isOn ? controller.action : "off",
            isUnavailable: !controller.sideAvailable,
            isOff: !controller.isOn,
            isInteractive: controller.canSetTarget,
            actionTextOverride: controller.sideAvailable ? (controller.hotFlashActive ? "Hot Flash" : (controller.isOn ? BedSideController.titleCase(controller.action) : "Off")) : nil,
            primaryValueOverride: controller.sideAvailable ? (controller.isOn ? BedLevel.format(target) : "OFF") : nil,
            primaryUnitOverride: .some(nil),
            targetCaption: controller.currentTemperature.map { .custom("Currently \(BedFormat.temperature($0))") } ?? .hidden
        )
        configuration.scale = .signedLevel
        let state = controller.sideAvailable ? (controller.isOn ? "\(BedSideController.titleCase(controller.action)), target \(BedLevel.format(target))" : "Off") : "Unavailable"
        let current = controller.currentTemperature.map { ", currently \(BedFormat.temperature($0))" } ?? ""
        configuration.readoutAccessibilityLabelOverride = "\(controller.config.title), \(state)\(current)"
        return configuration
    }
}

// MARK: - Scope prompt

/// "Tonight or All Nights?" after a target change during a schedule stage (web `BedTemperatureScopePrompt`).
struct BedTemperatureScopeSheet: View {
    var controller: BedSideController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HassTokens.Spacing.l) {
                    if let request = controller.scopeRequest {
                        Text("\(controller.config.title) • \(request.phase.label) • \(request.targetText)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(HassTokens.Ink.secondary)
                        Text("Choose whether this target applies only to the current night or also becomes the \(request.phase.label) setting for future nights.")
                            .font(.body)
                            .foregroundStyle(HassTokens.Ink.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    choice("Tonight", detail: "Change the current Pod target only.", symbol: "moon.stars", id: "bed.scope.tonight") {
                        controller.chooseScope(.tonight)
                    }
                    choice("All Nights", detail: "Update this schedule stage and tonight's target.", symbol: "calendar", id: "bed.scope.allNights") {
                        controller.chooseScope(.allNights)
                    }
                }
                .padding(HassTokens.Spacing.l)
            }
            .navigationTitle("Set Bed Temperature")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { controller.dismissScope() }.accessibilityIdentifier("bed.scope.cancel")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func choice(_ title: String, detail: String, symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            BedroomRow(symbol: symbol, title: title, lines: [detail]) {
                Image(systemName: "chevron.right").foregroundStyle(HassTokens.Ink.secondary).accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(id)
    }
}

// MARK: - Active alarm

/// "Alarm Active" with Snooze and Stop while the side's alarm rings or is snoozed (web `SleepypodActiveAlarmSection`).
struct ActiveBedAlarmSection: View {
    var controller: BedSideController

    var body: some View {
        let state = controller.alarmState
        if state.isActive {
            BedroomStyle.card(VStack(alignment: .leading, spacing: HassTokens.Spacing.m) {
                BedroomSectionHeader(title: "Alarm Active", detail: state == .ringing ? "Ringing" : "Snoozing")
                HStack(spacing: HassTokens.Spacing.m) {
                    Button { controller.snoozeAlarm() } label: {
                        VStack(spacing: 2) {
                            Label("Snooze", systemImage: "zzz").font(.body.weight(.semibold))
                            if state == .snoozed {
                                EverySecond { now in Text(controller.snoozeRemaining(now: now)).font(.footnote.monospacedDigit()) }
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 56)
                    }
                    // Filled like Stop: the bordered style's gray fill read 1.5:1 against the card in the audit.
                    .buttonStyle(.borderedProminent)
                    .tint(BedroomStyle.off)
                    .disabled(controller.alarmControlsReadOnly || state == .snoozed)
                    .accessibilityIdentifier("bed.alarm.snooze")
                    Button { controller.stopAlarm() } label: {
                        Label("Stop Alarm", systemImage: "stop.fill")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(BedroomStyle.danger)
                    .disabled(controller.alarmControlsReadOnly)
                    .accessibilityIdentifier("bed.alarm.stop")
                }
            })
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("bed.alarm.active")
        }
    }
}

// MARK: - Temperature tab

/// Bedtime, Asleep and Dawn level steppers (web `EightSleepScheduleTemperatureControl`).
struct BedScheduleTab: View {
    var controller: BedSideController

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.m) {
            BedroomSectionHeader(title: "Sleep Schedule", detail: "Recurring levels for each stage of the night.")
            ForEach(SchedulePhase.allCases, id: \.self) { phase in
                let level = controller.stageLevel(phase)
                let enabled = controller.canStepStage(phase)
                let range = controller.stageRange(phase).range
                BedroomRow(symbol: phase.symbol, title: phase.label,
                           lines: [controller.activePhase == phase ? "\(BedLevel.format(level)) · Now" : BedLevel.format(level)]) {
                    HStack(spacing: HassTokens.Spacing.s) {
                        stepButton("minus", label: "Lower \(phase.label)", id: "bed.stage.\(phase.rawValue).down",
                                   disabled: !enabled || (level ?? range.lowerBound) <= range.lowerBound) {
                            controller.stepStage(phase, up: false)
                        }
                        stepButton("plus", label: "Raise \(phase.label)", id: "bed.stage.\(phase.rawValue).up",
                                   disabled: !enabled || (level ?? range.upperBound) >= range.upperBound) {
                            controller.stepStage(phase, up: true)
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(phase.label) level")
                .accessibilityValue(BedLevel.format(level))
                .accessibilityAdjustableAction { direction in
                    guard enabled else { return }
                    switch direction {
                    case .increment: controller.stepStage(phase, up: true)
                    case .decrement: controller.stepStage(phase, up: false)
                    @unknown default: break
                    }
                }
                .accessibilityIdentifier("bed.stage.\(phase.rawValue)")
            }
        }
    }

    private func stepButton(_ symbol: String, label: String, id: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: HassTokens.minTarget, height: HassTokens.minTarget)
                .background(Color.primary.opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}

// MARK: - Special modes

/// Hot Flash Mode (web `EightSleepHotFlashControl`).
struct BedSpecialModesTab: View {
    var controller: BedSideController

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.m) {
            BedroomSectionHeader(title: "Special Modes", detail: "Activating hot flash mode will set the bed to -10 for fifteen minutes.")
            HStack(spacing: HassTokens.Spacing.m) {
                GlassTile(title: "Hot Flash Mode",
                          subtitle: controller.hotFlashAvailable ? (controller.hotFlashActive ? "Active" : "Inactive") : "Unavailable",
                          symbol: "snowflake", tint: BedroomStyle.cooling, isActive: controller.hotFlashActive,
                          isUnavailable: !controller.hotFlashAvailable || controller.scope.readOnly,
                          kind: .command) {
                    if !controller.hotFlashActive { controller.startHotFlash() }
                }
                .accessibilityIdentifier("bed.hotFlash")
                if controller.hotFlashActive {
                    VStack(spacing: HassTokens.Spacing.s) {
                        EverySecond { now in
                            Text(controller.hotFlashCountdown(now: now).map { "\($0) Remaining" } ?? "Cooling Bed")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(HassTokens.Ink.primary)
                        }
                        Button { controller.cancelHotFlash() } label: {
                            Image(systemName: "xmark")
                                .frame(width: HassTokens.minTarget, height: HassTokens.minTarget)
                        }
                        .buttonStyle(.bordered)
                        .disabled(controller.scope.readOnly)
                        .accessibilityLabel("Cancel Hot Flash Mode")
                        .accessibilityIdentifier("bed.hotFlash.cancel")
                    }
                }
            }
        }
    }
}

// MARK: - Alarms

/// Alarms grouped by day (web `EightSleepAlarmList`).
struct BedAlarmsTab: View {
    var controller: BedSideController
    @Binding var path: [BedSideSheet.Route]

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.m) {
            BedroomSectionHeader(title: "Alarms")
            if !controller.alarmsAvailable {
                BedroomNotice(message: "Home Assistant alarm schedule data is unavailable.")
            } else if controller.alarms.isEmpty {
                Text("No alarms yet. Add one to choose days and a time.")
                    .font(.subheadline)
                    .foregroundStyle(HassTokens.Ink.secondary)
            }
            ForEach(controller.alarmGroups) { group in
                Button { path.append(.day(group.day)) } label: {
                    BedroomRow(symbol: group.enabledCount > 0 ? "alarm" : "alarm.waves.left.and.right", title: group.title,
                               lines: [group.alarms.map { ClockTime.display($0.time) }.joined(separator: ", "), group.summary],
                               isMuted: group.enabledCount == 0) {
                        if group.alarms.count == 1, let alarm = group.alarms.first {
                            BedAlarmToggle(controller: controller, alarm: alarm)
                        } else {
                            Image(systemName: "chevron.right").foregroundStyle(HassTokens.Ink.secondary).accessibilityHidden(true)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("bed.alarms.\(group.day.rawValue)")
            }
            Button { path.append(.add(nil)) } label: {
                Label("Add Alarm", systemImage: "plus").frame(maxWidth: .infinity, minHeight: HassTokens.minTarget)
            }
            .buttonStyle(.borderedProminent)
            .tint(BedroomStyle.action)
            .disabled(!controller.alarmsEditable)
            .accessibilityIdentifier("bed.alarms.add")
        }
    }
}

/// An alarm's on/off switch.
struct BedAlarmToggle: View {
    var controller: BedSideController
    var alarm: BedAlarm

    var body: some View {
        Toggle("\(alarm.day.label) \(ClockTime.display(alarm.time)) alarm", isOn: Binding(
            get: { alarm.enabled }, set: { controller.setEnabled(alarm, $0) }
        ))
        .labelsHidden()
        .disabled(!controller.alarmsEditable)
        .accessibilityIdentifier("bed.alarm.\(alarm.day.rawValue).\(alarm.time).enabled")
    }
}

/// One day's alarms (web `EightSleepAlarmDayPage`).
struct BedAlarmDayPage: View {
    let devices: BedroomDevices
    let side: BedSide
    let day: Weekday
    @Binding var path: [BedSideSheet.Route]

    private var controller: BedSideController { devices.bed(side) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HassTokens.Spacing.m) {
                ActiveBedAlarmSection(controller: controller)
                let alarms = controller.alarms.filter { $0.day == day }.sorted { ClockTime.minutes($0.time) < ClockTime.minutes($1.time) }
                if alarms.isEmpty {
                    Text("No alarms yet. Add one to choose days and a time.")
                        .font(.subheadline)
                        .foregroundStyle(HassTokens.Ink.secondary)
                }
                ForEach(alarms) { alarm in
                    Button { path.append(.edit(alarm.id)) } label: {
                        BedroomRow(symbol: alarm.enabled ? "alarm" : "alarm.waves.left.and.right", title: ClockTime.display(alarm.time),
                                   lines: [alarm.enabled ? "Enabled" : "Disabled"], isMuted: !alarm.enabled) {
                            BedAlarmToggle(controller: controller, alarm: alarm)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("bed.day.alarm.\(alarm.time)")
                }
                Button { path.append(.add(day)) } label: {
                    Label("Add Alarm", systemImage: "plus").frame(maxWidth: .infinity, minHeight: HassTokens.minTarget)
                }
                .buttonStyle(.borderedProminent)
                .tint(BedroomStyle.action)
                .disabled(!controller.alarmsEditable)
                .accessibilityIdentifier("bed.day.add")
            }
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .padding(HassTokens.Spacing.l)
        }
        .navigationTitle("\(day.label) Alarms")
        .inlineNavigationTitle()
    }
}

/// Adds or edits a bed alarm (web `EightSleepAlarmEditor`).
struct BedAlarmEditor: View {
    let devices: BedroomDevices
    let side: BedSide
    var onDone: () -> Void
    @State private var draft: BedSideController.AlarmDraft
    @State private var confirmingDelete = false
    @State private var saving = false

    init(devices: BedroomDevices, side: BedSide, alarmId: String?, lockedDay: Weekday?, onDone: @escaping () -> Void) {
        self.devices = devices
        self.side = side
        self.onDone = onDone
        let controller = devices.bed(side)
        let alarm = alarmId.flatMap { id in controller.alarms.first { $0.id == id } }
        _draft = State(initialValue: alarm.map { controller.editDraft($0, wakeLight: devices.wakeLight.snapshot) }
            ?? controller.newAlarmDraft(lockedDay: lockedDay))
    }

    private var controller: BedSideController { devices.bed(side) }
    private var problems: [String] { controller.problems(draft) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HassTokens.Spacing.xl) {
                ActiveBedAlarmSection(controller: controller)
                if let error = devices.wakeLight.error { BedroomNotice(message: error, tone: .error) }
                if draft.lockedDay == nil {
                    WeekdayPicker(title: "Days", days: $draft.days, identifier: "bed.editor.day")
                }
                ClockTimeField(title: "Time", time: $draft.time, identifier: "bed.editor.time")
                if draft.editingId != nil {
                    Toggle("Alarm Enabled", isOn: $draft.enabled)
                        .frame(minHeight: HassTokens.minTarget)
                        .accessibilityIdentifier("bed.editor.enabled")
                }
                Toggle("Use Room Wake Lights", isOn: $draft.wakeLightEnabled)
                    .frame(minHeight: HassTokens.minTarget)
                    .accessibilityIdentifier("bed.editor.wakeLight")
                ForEach(problems, id: \.self) { BedroomNotice(message: $0) }
                Button { save() } label: {
                    Text(saving ? "Saving…" : "Save").frame(maxWidth: .infinity, minHeight: HassTokens.minTarget)
                }
                .buttonStyle(.borderedProminent)
                .tint(BedroomStyle.action)
                .disabled(saving || !problems.isEmpty)
                .accessibilityIdentifier("bed.editor.save")
                if draft.editingId != nil {
                    Button(role: .destructive) { confirmingDelete = true } label: {
                        Text("Delete").frame(maxWidth: .infinity, minHeight: HassTokens.minTarget)
                    }
                    .buttonStyle(.borderedProminent) // Filled like Stop: red on the bordered pink fill missed 4.5:1.
                    .tint(BedroomStyle.danger)
                    .disabled(saving || !controller.alarmsEditable)
                    .accessibilityIdentifier("bed.editor.delete")
                }
            }
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .padding(HassTokens.Spacing.l)
        }
        .navigationTitle(draft.title)
        .inlineNavigationTitle()
        .confirmationDialog(deletePrompt, isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Alarm", role: .destructive) { remove() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var deletePrompt: String {
        "Delete alarm set for \(ClockTime.display(draft.time)) on \(draft.days.first?.label ?? "")?"
    }

    private func save() {
        saving = true
        Task {
            let ok = await controller.save(draft, wakeLight: devices.wakeLight)
            saving = false
            if ok { onDone() }
        }
    }

    private func remove() {
        saving = true
        Task {
            let ok = await controller.delete(draft, wakeLight: devices.wakeLight)
            saving = false
            if ok { onDone() }
        }
    }
}

// MARK: - Status

/// Pod readings (web `EightSleepStatusPanel`, climate mode).
struct BedStatusTab: View {
    struct Reading {
        var title: String
        var value: String
        var symbol: String
    }

    var controller: BedSideController
    @ScaledMetric(relativeTo: .body) private var minWidth: CGFloat = 150

    var body: some View {
        let config = controller.config
        let entity = { (id: String) in controller.store.entity(id).state }
        let pumpProblem = entity(config.pumpClogEntityId)?.state == "on" || entity(config.pumpStallEntityId)?.state == "on"
        let rows = [
            Reading(title: "Current Temp", value: BedFormat.temperature(controller.currentTemperature), symbol: "thermometer.medium"),
            Reading(title: "Pump Status", value: pumpProblem ? "Check pump" : "OK", symbol: "drop"),
            Reading(title: "Loop Temp", value: BedFormat.metric(entity(config.pumpLoopTemperatureEntityId)), symbol: "arrow.triangle.2.circlepath"),
            Reading(title: "Pump RPM", value: BedFormat.metric(entity(config.pumpRpmEntityId)), symbol: "gauge.with.dots.needle.33percent"),
            Reading(title: "Heart Rate", value: BedFormat.metric(entity(config.heartRateEntityId)), symbol: "heart"),
            Reading(title: "Breathing", value: BedFormat.metric(entity(config.breathingRateEntityId)), symbol: "lungs"),
            Reading(title: "HRV", value: BedFormat.metric(entity(config.hrvEntityId)), symbol: "waveform.path.ecg"),
        ]
        VStack(alignment: .leading, spacing: HassTokens.Spacing.m) {
            BedroomSectionHeader(title: "Status")
            DynamicGridLayout(minCellWidth: minWidth, maxColumns: 3) {
                ForEach(rows, id: \.title) { reading in
                    BedroomStyle.card(VStack(alignment: .leading, spacing: HassTokens.Spacing.xs) {
                        Label(reading.title, systemImage: reading.symbol).font(.subheadline).foregroundStyle(HassTokens.Ink.secondary)
                        Text(reading.value).font(.title3.weight(.semibold).monospacedDigit()).foregroundStyle(HassTokens.Ink.primary)
                    })
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("bed.status.\(reading.title)")
                }
            }
        }
    }
}

// MARK: - Tile

/// A bed side's room tile (web SleepyPod tile).
public struct BedSideTile: View {
    var controller: BedSideController
    var action: () -> Void

    /// Creates the tile.
    public init(controller: BedSideController, action: @escaping () -> Void) {
        self.controller = controller
        self.action = action
    }

    public var body: some View {
        EverySecond { now in
            GlassTile(title: controller.config.title, subtitle: controller.tileSubtitle(now: now), symbol: "bed.double",
                      tint: BedroomStyle.tint(action: controller.action),
                      isActive: controller.isOn && !controller.scope.readOnly,
                      kind: .navigate, action: action)
        }
        .accessibilityIdentifier("tile.bed.\(controller.config.id)")
    }
}
