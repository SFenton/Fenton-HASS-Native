import HassCore
import HassDesign
import SwiftUI

/// The room's wake-light alarms sheet (pattern: `.agents/patterns/bedroom-devices.md`; web `WakeLightModal`).
///
/// Two tabs in the bottom section bar (direction G, Sheets): the alarm schedule (with stop controls while a wake
/// runs) and room defaults. Adding or editing an alarm pushes an editor inside the sheet. Mirrored bed alarms open their bed's sheet through `onOpenBed`.
public struct WakeLightSheet: View {
    /// A sheet tab.
    public enum Tab: String, CaseIterable, Identifiable, Sendable {
        case alarms, defaults
        public var id: String { rawValue }
        var title: String { self == .alarms ? "Wake Alarms" : "Defaults" }
    }

    /// An editor page.
    enum Route: Hashable {
        case add
        case edit(String)
    }

    let devices: BedroomDevices
    var onOpenBed: (BedSide) -> Void
    @State private var tab: Tab
    @State private var path: [Route] = []
    @Environment(\.dismiss) private var dismiss

    /// Creates the sheet.
    /// - Parameters:
    ///   - devices: The room's controllers.
    ///   - initialTab: The tab shown first.
    ///   - onOpenBed: Opens a bed side's alarms (the host closes this sheet first).
    public init(devices: BedroomDevices, initialTab: Tab = .alarms, onOpenBed: @escaping (BedSide) -> Void = { _ in }) {
        self.devices = devices
        self.onOpenBed = onOpenBed
        _tab = State(initialValue: initialTab)
    }

    private var controller: WakeLightController { devices.wakeLight }

    public var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: HassTokens.Spacing.xl) {
                    Text(WakeLight.subtitle(controller.snapshot, modal: true))
                        .font(.subheadline)
                        .foregroundStyle(HassTokens.Ink.secondary)
                        .accessibilityIdentifier("wake.subtitle")
                    alerts
                    switch tab {
                    case .alarms: alarmsTab
                    case .defaults: WakeLightDefaultsTab(controller: controller)
                    }
                }
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
                .padding(HassTokens.Spacing.l)
            }
            .modalChrome()
            .modalTabBar(Tab.allCases, label: "\(controller.config.title) sections", title: \.title,
                         symbol: ModalTabSymbols.symbol(for:), selection: $tab,
                         identifier: "wake.tabs")
            .navigationTitle(controller.config.title) // With the room name the bar title clips at AX5.
            .inlineNavigationTitle()
            .toolbar { SheetCloseItem { dismiss() } }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .add: WakeLightEditor(devices: devices, alarmId: nil) { path.removeAll() }.modalChrome()
                case let .edit(id): WakeLightEditor(devices: devices, alarmId: id) { path.removeAll() }.modalChrome()
                }
            }
        }
    }

    // MARK: - Alerts

    @ViewBuilder private var alerts: some View {
        let snapshot = controller.live
        if !snapshot.compatible && snapshot.contractVersion > 0 {
            BedroomNotice(message: "Editing wake light alarms requires an integration update. Saved alarms remain available to view.")
        } else if !snapshot.available {
            BedroomNotice(message: WakeLight.errorMessage("unavailable"))
        }
        if let error = controller.error, path.isEmpty {
            BedroomNotice(message: error, tone: .error)
                .accessibilityIdentifier("wake.error")
        }
    }

    // MARK: - Wake Alarms tab

    @ViewBuilder private var alarmsTab: some View {
        let snapshot = controller.snapshot
        if !snapshot.activeOccurrences.isEmpty { activeControls(snapshot) }
        ForEach(snapshot.currentBlockers, id: \.self) { code in
            BedroomNotice(message: WakeLight.blockerMessage(code))
        }
        VStack(alignment: .leading, spacing: HassTokens.Spacing.m) {
            BedroomSectionHeader(title: "Wake Alarm Schedule")
            if snapshot.alarms.isEmpty {
                Text("No wake alarms yet.")
                    .font(.subheadline)
                    .foregroundStyle(HassTokens.Ink.secondary)
            }
            ForEach(snapshot.alarms) { alarm in
                if alarm.isNative { nativeRow(alarm) } else { mirroredRow(alarm, snapshot: snapshot) }
            }
            if controller.canEdit {
                Button { path.append(.add) } label: {
                    Label("Add Wake Alarm", systemImage: "plus")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!snapshot.available || controller.configurationPending)
                .accessibilityIdentifier("wake.add")
            } else {
                Text("Only Home Assistant administrators can edit wake alarms.")
                    .font(.footnote)
                    .foregroundStyle(HassTokens.Ink.secondary)
            }
        }
    }

    private func activeControls(_ snapshot: WakeLight.Snapshot) -> some View {
        BedroomStyle.card(VStack(alignment: .leading, spacing: HassTokens.Spacing.m) {
            BedroomSectionHeader(title: "Active Wake-Light Controls",
                                 detail: "Stopping ends this wake for the room and leaves the lights as they are.")
            ForEach(snapshot.activeOccurrences) { occurrence in
                let alarm = snapshot.alarms.first { $0.id == occurrence.alarmId }
                Text("\(alarm?.label ?? "Wake Alarm") · \(WakeLight.displayTime(occurrence.wakeAt))")
                    .font(.subheadline)
                    .foregroundStyle(HassTokens.Ink.primary)
            }
            Button(role: .destructive) {
                Task { await controller.endEpisode() }
            } label: {
                Text(controller.stopping ? "Stopping Wake Lights…" : "Stop Wake-Light Episode")
                    .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget)
            }
            .buttonStyle(.borderedProminent)
            .tint(BedroomStyle.danger)
            .disabled(controller.stopping || !controller.live.available)
            .accessibilityIdentifier("wake.stop")
        })
    }

    private func nativeRow(_ alarm: WakeLight.Alarm) -> some View {
        let pending = controller.isPending(alarmId: alarm.id)
        let editable = controller.canEdit && controller.live.available
        return BedroomRow(
            symbol: alarm.enabled ? "alarm" : "alarm.waves.left.and.right",
            title: alarm.label,
            lines: ["\(WakeLight.scheduleLabel(alarm)) · \(WakeLight.displayTime(alarm.localTime))",
                    "Ramp: \(WakeLight.rampLabel(alarm.rampMinutes))"],
            isMuted: !alarm.enabled,
            onOpen: editable ? { path.append(.edit(alarm.id)) } : nil,
            openIdentifier: "wake.alarm.\(alarm.id)"
        ) {
            Toggle(alarm.label, isOn: Binding(get: { alarm.enabled }, set: { enabled in
                var next = alarm
                next.enabled = enabled
                Task { await controller.save(next) }
            }))
            .labelsHidden()
            .disabled(!editable || pending)
            .accessibilityIdentifier("wake.alarm.\(alarm.id).enabled")
        }
        .accessibilityElement(children: .contain)
    }

    private func mirroredRow(_ alarm: WakeLight.Alarm, snapshot: WakeLight.Snapshot) -> some View {
        let source = alarm.sourceRef.flatMap(controller.config.source(id:))
        let keys = alarm.linkKeys()
        let linked = snapshot.isLinked(alarm)
        let title = source?.alarmLabel ?? alarm.sourceLabel ?? alarm.label
        return VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
            BedroomRow(
                symbol: "bed.double",
                title: title,
                lines: ["\(WakeLight.scheduleLabel(alarm)) · \(WakeLight.displayTime(alarm.localTime))"],
                isMuted: !alarm.enabled || !linked
            ) {
                Toggle("Use room wake lights for the \(title) alarm", isOn: Binding(get: { linked }, set: { enabled in
                    Task { await controller.setLinks(keys, enabled: enabled) }
                }))
                .labelsHidden()
                .disabled(!controller.canEdit || !controller.live.available || keys.isEmpty || controller.arePending(linkKeys: keys))
                .accessibilityIdentifier("wake.alarm.\(alarm.id).link")
            }
            if let source {
                Button {
                    dismiss()
                    onOpenBed(source.side)
                } label: {
                    Label("Open Linked-Device Alarm Editor", systemImage: "arrow.up.forward.app")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(HassTokens.Ink.primary) // The accent renders 2.5:1 on the card.
                        .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("wake.alarm.\(alarm.id).open")
            }
        }
    }
}

// MARK: - Defaults

/// Room ramp and post-wake hold (web Defaults tab).
struct WakeLightDefaultsTab: View {
    var controller: WakeLightController

    var body: some View {
        let snapshot = controller.snapshot
        let editable = controller.canEdit && controller.live.available && !controller.configurationPending
        let holdSupported = snapshot.contractVersion >= 6
        VStack(alignment: .leading, spacing: HassTokens.Spacing.xl) {
            BedroomSectionHeader(title: "Wake-Light Defaults", detail: "New wake alarms start with this light ramp.")
            ChoiceGrid(title: "Light Ramp Duration", options: WakeLight.rampMinutes, label: WakeLight.durationLabel,
                       selection: binding(\.rampMinutes), isDisabled: !editable, identifier: "wake.defaults.ramp")
            ChoiceGrid(title: "Post-Wake Hold Time", options: WakeLight.holdMinutes, label: WakeLight.durationLabel,
                       selection: binding(\.postWakeHoldMinutes), isDisabled: !editable || !holdSupported, identifier: "wake.defaults.hold")
            Text(holdSupported
                 ? "How long the lights stay at full brightness after the wake time before normal lighting resumes."
                 : "Post-wake hold requires a wake light integration update.")
                .font(.footnote)
                .foregroundStyle(HassTokens.Ink.secondary)
        }
    }

    private func binding(_ keyPath: WritableKeyPath<WakeLight.Defaults, Int>) -> Binding<Int> {
        Binding(get: { controller.snapshot.defaults[keyPath: keyPath] }, set: { value in
            var next = controller.snapshot.defaults
            guard next[keyPath: keyPath] != value else { return }
            next[keyPath: keyPath] = value
            Task { await controller.updateDefaults(next) }
        })
    }
}

// MARK: - Editor

/// Adds or edits one wake alarm (web `WakeLightAlarmEditor`).
struct WakeLightEditor: View {
    let devices: BedroomDevices
    let alarmId: String?
    var onDone: () -> Void

    @State private var draft: WakeLight.Alarm
    @State private var initial: WakeLight.Alarm
    @State private var addToBeds: Set<BedSide> = []
    @State private var confirmingDelete = false
    @State private var saving = false

    init(devices: BedroomDevices, alarmId: String?, onDone: @escaping () -> Void) {
        self.devices = devices
        self.alarmId = alarmId
        self.onDone = onDone
        let existing = alarmId.flatMap { id in devices.wakeLight.snapshot.alarms.first { $0.id == id } }
        let start = existing ?? WakeLight.Alarm.new(id: UUID().uuidString.lowercased(), defaults: devices.wakeLight.snapshot.defaults)
        var weekly = start
        if existing == nil {
            weekly.kind = .weekly
            weekly.weekdays = Weekday.workdays
            weekly.date = nil
        }
        _draft = State(initialValue: weekly)
        _initial = State(initialValue: weekly)
    }

    private var controller: WakeLightController { devices.wakeLight }
    private var isNew: Bool { alarmId == nil }
    private var problems: [String] { WakeLight.problems(draft) }
    private var dirty: Bool { isNew || !draft.sameEdits(as: initial) }
    private var locked: Bool { !controller.live.available || !controller.canEdit || controller.configurationPending || saving }
    private var latest: WakeLight.Alarm? { alarmId.flatMap { id in controller.live.alarms.first { $0.id == id } } }
    private var stale: Bool {
        controller.errorCode == "revision_conflict" && (controller.requiresAlarmReload || (latest.map { $0.revision != draft.revision } ?? false))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HassTokens.Spacing.xl) {
                if let error = controller.error { BedroomNotice(message: error, tone: .error).accessibilityIdentifier("wake.editor.error") }
                if stale {
                    Button("Open Latest Alarm, Replace Draft") { reload() }
                        .frame(minHeight: HassTokens.minTarget)
                        .accessibilityIdentifier("wake.editor.reload")
                }
                fields
                if !problems.isEmpty && dirty {
                    VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
                        ForEach(problems, id: \.self) { BedroomNotice(message: $0) }
                    }
                }
                buttons
            }
            .disabled(saving)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
            .padding(HassTokens.Spacing.l)
        }
        .navigationTitle(isNew ? "Add Wake Alarm" : initial.label)
        .inlineNavigationTitle()
        .onDisappear { controller.clearError() }
        .confirmationDialog("Delete alarm set for \(WakeLight.displayTime(initial.localTime)) on \(WakeLight.scheduleLabel(initial))?",
                            isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Alarm", role: .destructive) { remove() }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder private var fields: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
            Text("Alarm Type").font(.subheadline.weight(.semibold)).foregroundStyle(HassTokens.Ink.primary)
            SegmentedChoice(label: "Alarm Type", options: WakeLight.Kind.allCases, title: \.label, selection: draft.kind,
                            identifier: "wake.editor.kind") { kindBinding.wrappedValue = $0 }
        }
        VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
            Text("Alarm Name").font(.subheadline.weight(.semibold)).foregroundStyle(HassTokens.Ink.primary)
            // Grows with Dynamic Type: the rounded-border (UITextField) style keeps a fixed height and clipped at AX5.
            TextField("Alarm Name", text: Binding(get: { draft.label }, set: {
                draft.label = String($0.filter { $0 != "\n" }.prefix(40))
            }), axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(.plain)
                .padding(.horizontal, HassTokens.Spacing.m)
                .padding(.vertical, HassTokens.Spacing.s)
                .frame(minHeight: HassTokens.minTarget)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.secondary.opacity(0.4)))
                .accessibilityIdentifier("wake.editor.name")
        }
        if draft.kind == .weekly {
            WeekdayPicker(title: "Days", days: $draft.weekdays, identifier: "wake.editor.day")
        }
        ClockTimeField(title: "Wake Time", time: $draft.localTime, identifier: "wake.editor.time")
        if draft.kind == .once {
            DatePicker("Alarm Date", selection: Binding(
                get: { draft.date.flatMap { WakeLight.date($0) } ?? .now },
                set: { draft.date = WakeLight.dateString($0) }
            ), displayedComponents: .date)
            .frame(minHeight: HassTokens.minTarget)
            .accessibilityIdentifier("wake.editor.date")
        }
        ChoiceGrid(title: "Light Ramp Duration", options: WakeLight.rampMinutes, label: WakeLight.durationLabel,
                   selection: $draft.rampMinutes, identifier: "wake.editor.ramp")
        Toggle("Wake Alarm Enabled", isOn: $draft.enabled)
            .frame(minHeight: HassTokens.minTarget)
            .accessibilityIdentifier("wake.editor.enabled")
        if isNew { bedToggles }
    }

    @ViewBuilder private var bedToggles: some View {
        let oneTimeUnsupported = draft.kind == .once && controller.snapshot.contractVersion < 5
        ForEach(devices.bedTargets) { target in
            Toggle("Add to \(target.title)", isOn: Binding(
                get: { addToBeds.contains(target.side) },
                set: { if $0 { addToBeds.insert(target.side) } else { addToBeds.remove(target.side) } }
            ))
            .frame(minHeight: HassTokens.minTarget)
            .disabled(!target.available || oneTimeUnsupported)
            .accessibilityIdentifier("wake.editor.bed.\(target.side.rawValue)")
        }
        if oneTimeUnsupported {
            Text("Adding one-time alarms to a bed requires a wake light integration update.")
                .font(.footnote)
                .foregroundStyle(HassTokens.Ink.secondary)
        }
    }

    private var buttons: some View {
        VStack(spacing: HassTokens.Spacing.m) {
            Button { save() } label: {
                Text(saving ? "Saving…" : "Save")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(locked || !dirty || !problems.isEmpty || stale)
            .accessibilityIdentifier("wake.editor.save")
            if !isNew {
                Button(role: .destructive) { confirmingDelete = true } label: {
                    Text("Delete").frame(maxWidth: .infinity, minHeight: HassTokens.minTarget)
                }
                .buttonStyle(.borderedProminent) // Filled like Stop: red on the bordered pink fill missed 4.5:1.
                .tint(BedroomStyle.danger)
                .disabled(locked)
                .accessibilityIdentifier("wake.editor.delete")
            }
        }
    }

    private var kindBinding: Binding<WakeLight.Kind> {
        Binding(get: { draft.kind }, set: { kind in
            guard kind != draft.kind else { return }
            draft.kind = kind
            if kind == .once {
                draft.date = draft.date ?? WakeLight.dateString(Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now)
            } else if draft.weekdays.isEmpty {
                draft.weekdays = Weekday.workdays
            }
        })
    }

    private func save() {
        saving = true
        Task {
            let ok = await devices.saveWakeAlarm(draft, isNew: isNew, addToBeds: addToBeds)
            saving = false
            if ok { onDone() }
        }
    }

    private func remove() {
        guard let alarmId else { return }
        saving = true
        Task {
            let ok = await controller.delete(alarmId: alarmId)
            saving = false
            if ok { onDone() }
        }
    }

    private func reload() {
        if let latest {
            draft = latest
            initial = latest
        }
        controller.clearError()
    }
}

// MARK: - Tile

/// The room tile for the wake light (web "Wake-Light Alarms" tile).
public struct WakeLightTile: View {
    var controller: WakeLightController
    var action: () -> Void

    /// Creates the tile.
    public init(controller: WakeLightController, action: @escaping () -> Void) {
        self.controller = controller
        self.action = action
    }

    public var body: some View {
        let snapshot = controller.snapshot
        GlassTile(title: controller.config.title, subtitle: WakeLight.subtitle(snapshot), symbol: "sunrise",
                  family: .lights,
                  isActive: snapshot.available && snapshot.alarms.contains(where: \.enabled),
                  kind: .navigate, action: action)
            .accessibilityIdentifier("tile.wakeLight")
    }
}
