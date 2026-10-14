import HassCore
import HassDesign
import SwiftUI

/// The Schedules tab (web `SchedulesPanel` over `ScheduleCollection`): the scheduling switch, the activities, and Add.
struct HumidifierSchedulesTab: View {
    var schedules: HumidifierScheduleController
    var onEdit: (HumidifierScheduleRule) -> Void
    var onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.xl) {
            VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
                Toggle(isOn: Binding(get: { schedules.enabled }, set: { _ in schedules.toggleEnabled() })) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(schedules.toggleTitle).font(.body.weight(.semibold))
                            Text(schedules.toggleSubtitle).font(.footnote).foregroundStyle(HassTokens.Ink.secondary)
                        }
                    } icon: {
                        Image(systemName: "calendar")
                    }
                }
                .foregroundStyle(HassTokens.Ink.primary)
                .disabled(schedules.toggleDisabled)
                .padding(HassTokens.Spacing.m)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: HassTokens.Radius.tile, style: .continuous))
                .accessibilityIdentifier("humidifier.scheduling")
                Text("Schedules run on Home Assistant. Manual changes last until the next activity or restart/reconnect recovery.")
                    .font(.footnote)
                    .foregroundStyle(HassTokens.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let error = schedules.error { InlineAlert(error) }

            DeviceSection(title: "Activities") {
                if schedules.loading && !schedules.ready {
                    ProgressView("Loading scheduled activities…")
                        .progressViewStyle(.arc(.compact))
                        .foregroundStyle(HassTokens.Ink.secondary)
                } else if schedules.rules.isEmpty {
                    Text("No activities yet. Add morning, evening, or overnight profiles.")
                        .font(.subheadline)
                        .foregroundStyle(HassTokens.Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(spacing: HassTokens.Spacing.s) {
                        ForEach(schedules.rules) { rule in row(rule) }
                    }
                }
            }

            if schedules.canEdit {
                Button(action: onAdd) {
                    // Primary ink: system blue on the bordered fill measured 2.1:1 on the iPad sheet.
                    Label("Add Scheduled Activity", systemImage: "plus")
                        .foregroundStyle(HassTokens.Ink.primary)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(schedules.loading || schedules.saving || !schedules.ready)
                .accessibilityIdentifier("humidifier.addActivity")
            } else {
                Text("Only Home Assistant administrators can edit scheduled activities.")
                    .font(.footnote)
                    .foregroundStyle(HassTokens.Ink.secondary)
            }
        }
    }

    private func row(_ rule: HumidifierScheduleRule) -> some View {
        let running = schedules.isRunning(rule)
        return Button { onEdit(rule) } label: {
            HStack(spacing: HassTokens.Spacing.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.label).font(.body.weight(.semibold)).foregroundStyle(HassTokens.Ink.primary)
                    Text("\(HumidifierSchedule.formatDays(rule.days)) · \(HumidifierSchedule.formatTimes(start: rule.start, end: rule.end))")
                        .font(.subheadline)
                        .foregroundStyle(HassTokens.Ink.secondary)
                    Text(HumidifierSchedule.profileSummary(rule) + (running ? " • Active now" : ""))
                        .font(.footnote)
                        .foregroundStyle(running ? Color(RoomDeviceStyle.humidifierTint) : HassTokens.Ink.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(HassTokens.Spacing.m)
            .frame(minHeight: HassTokens.minTarget)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: HassTokens.Radius.tile, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: HassTokens.Radius.tile, style: .continuous)
                    .strokeBorder(running ? Color(RoomDeviceStyle.humidifierTint) : .clear, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: HassTokens.Radius.tile, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!schedules.canEdit || schedules.saving)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("humidifier.activity.\(rule.label)")
    }
}

/// The pushed editor for one activity (web `ScheduleEditor` + `ScheduleDetailFooter`).
struct HumidifierActivityEditor: View {
    var schedules: HumidifierScheduleController
    var isNew: Bool
    var onClose: () -> Void
    @State private var draft: HumidifierScheduleRule
    @State private var confirmingDelete = false

    init(schedules: HumidifierScheduleController, rule: HumidifierScheduleRule, isNew: Bool, onClose: @escaping () -> Void) {
        self.schedules = schedules
        self.isNew = isNew
        self.onClose = onClose
        _draft = State(initialValue: rule)
    }

    private var conflict: ScheduleConflict? { schedules.conflict(for: draft) }
    private var canSave: Bool { draft.isComplete && conflict == nil && !schedules.saving }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HassTokens.Spacing.xl) {
                DeviceSection(title: "Name") {
                    TextField("Name", text: Binding(get: { draft.label }, set: { draft.label = String($0.prefix(40)) }))
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("activity.name")
                }
                DeviceSection(title: "Days") {
                    DynamicGridLayout(minCellWidth: 64, maxColumns: 7) {
                        ForEach(Weekday.allCases, id: \.self) { day in
                            Toggle(day.shortTitle, isOn: Binding(get: { draft.days.contains(day) }, set: { on in
                                draft.days = Weekday.allCases.filter { $0 == day ? on : draft.days.contains($0) }
                            }))
                            .toggleStyle(.button)
                            .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget)
                            .accessibilityLabel(day.title)
                            .accessibilityIdentifier("activity.day.\(day.rawValue)")
                        }
                    }
                }
                DeviceSection(title: "Time") {
                    DatePicker("Start", selection: timeBinding(\.start), displayedComponents: .hourAndMinute)
                        .accessibilityIdentifier("activity.start")
                    DatePicker("End", selection: timeBinding(\.end), displayedComponents: .hourAndMinute)
                        .accessibilityIdentifier("activity.end")
                }
                .foregroundStyle(HassTokens.Ink.primary)
                DeviceSection(title: "Mode") {
                    Picker("Mode", selection: Binding(get: { draft.mode }, set: { mode in
                        draft.mode = mode
                        if mode == .sleep { draft.display = false }
                    })) {
                        ForEach(HumidifierMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .frame(minHeight: HassTokens.minTarget)
                    .accessibilityIdentifier("activity.mode")
                }
                if draft.mode != .sleep { profileFields }
                if draft.days.isEmpty { InlineAlert("Select at least one day.") }
                if !HumidifierSchedule.isValidTime(draft.start) || !HumidifierSchedule.isValidTime(draft.end) {
                    InlineAlert("Choose valid start and end times.")
                }
                if let message = conflict?.message ?? schedules.error { InlineAlert(message) }
                if !isNew {
                    Button(role: .destructive) { confirmingDelete = true } label: {
                        Label("Delete Activity", systemImage: "trash").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(schedules.saving)
                    .accessibilityIdentifier("activity.delete")
                    .confirmationDialog("Delete \(draft.label)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                        Button("Delete Activity", role: .destructive) {
                            Task { if await schedules.delete(draft.id) { onClose() } }
                        }
                    }
                }
            }
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .padding(HassTokens.Spacing.l)
        }
        .navigationTitle(isNew ? "Add Activity" : draft.label)
        .inlineNavigationTitle()
        .navigationBarBackButtonHiddenIfAvailable(schedules.saving)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(schedules.saving ? "Saving…" : "Save") {
                    Task { if await schedules.save(draft) { onClose() } }
                }
                .disabled(!canSave)
                .accessibilityIdentifier("activity.save")
            }
        }
    }

    /// Mist, target humidity, warm mist and display (hidden in Sleep, which runs its own profile).
    private var profileFields: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.xl) {
            DynamicGridLayout(minCellWidth: 260, maxColumns: 2) {
                DeviceSection(title: "Mist Level") {
                    ThermostatDial(HumidifierDials.scheduledMist(draft.mistLevel), size: .compact) { targets in
                        if case let .single(value) = targets { draft.mistLevel = Int(value.rounded()) }
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("activity.mistDial")
                }
                if draft.mode == .targetHumidity {
                    DeviceSection(title: "Target Humidity") {
                        ThermostatDial(HumidifierDials.scheduledTarget(draft.targetHumidity), size: .compact) { targets in
                            if case let .single(value) = targets { draft.targetHumidity = Int(value.rounded()) }
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("activity.targetDial")
                    }
                }
            }
            DeviceSection(title: "Warm Mist") {
                DeviceTileGrid {
                    ForEach(HumidifierConfig.warmLevels) { level in
                        RemoteGlassTile(title: level.title, symbol: SymbolMap.symbol(for: level.icon), tint: RoomDeviceStyle.mode,
                                        isActive: draft.warmLevel == level.value, isDisabled: false,
                                        semantics: .selection(isSelected: draft.warmLevel == level.value)) {
                            draft.warmLevel = level.value
                        }
                        .accessibilityIdentifier("activity.warm.\(level.title)")
                    }
                }
            }
            DeviceSection(title: "Display") {
                Toggle(isOn: $draft.display) { Label("Display", systemImage: "display") }
                    .foregroundStyle(HassTokens.Ink.primary)
                    .frame(minHeight: HassTokens.minTarget)
                    .accessibilityIdentifier("activity.display")
            }
        }
    }

    private func timeBinding(_ keyPath: WritableKeyPath<HumidifierScheduleRule, String>) -> Binding<Date> {
        Binding(get: { ActivityTime.date(from: draft[keyPath: keyPath]) },
                set: { draft[keyPath: keyPath] = ActivityTime.string(from: $0) })
    }
}

/// `HH:mm` ⇄ a time today, for the time pickers.
enum ActivityTime {
    static func date(from value: String, calendar: Calendar = .current, now: Date = Date()) -> Date {
        let normalized = HumidifierSchedule.normalizedTime(value, fallback: "00:00")
        let hour = min(23, Int(normalized.prefix(2)) ?? 0)
        let minute = Int(normalized.suffix(2)) ?? 0
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) ?? now
    }

    static func string(from date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}

private extension View {
    /// Hides Back while saving so the editor can't be left mid-save.
    @ViewBuilder
    func navigationBarBackButtonHiddenIfAvailable(_ hidden: Bool) -> some View {
        #if os(iOS)
        navigationBarBackButtonHidden(hidden)
        #else
        self
        #endif
    }
}
