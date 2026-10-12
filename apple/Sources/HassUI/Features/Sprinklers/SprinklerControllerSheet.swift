import HassCore
import HassDesign
import SwiftUI

/// A detail page in a controller's sheet (web `DETAIL_WATER` / `DETAIL_SCHEDULE`).
public enum SprinklerDetail: Hashable, Sendable {
    /// Water a zone now.
    case water(zone: Int)
    /// Edit a zone's program.
    case schedule(zone: Int)
}

/// A controller's sheet (web `SprinklerController.tsx` modal): status, zones, Stop watering, rain delay and smart
/// watering, and each program. A zone pushes Water now; a program pushes its schedule editor (HIG: Sheets, a
/// navigation stack inside the sheet in place of the web's in-modal detail pages).
struct SprinklerControllerSheet: View {
    var controller: SprinklerController
    @State private var path: [SprinklerDetail]
    @Environment(\.dismiss) private var dismiss
    private let format = SprinklerFormat()
    @ScaledMetric(relativeTo: .footnote) private var minPillWidth: CGFloat = 150

    init(controller: SprinklerController, initialDetail: SprinklerDetail? = nil) {
        self.controller = controller
        _path = State(initialValue: initialDetail.map { [$0] } ?? [])
    }

    var body: some View {
        NavigationStack(path: $path) {
            overview
                .navigationTitle(controller.config.title)
                .inlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
                .navigationDestination(for: SprinklerDetail.self) { detail in
                    switch detail {
                    case let .water(zone): SprinklerWaterPage(controller: controller, zone: zone) { pop() }
                    case let .schedule(zone): SprinklerSchedulePage(controller: controller, zone: zone) { pop() }
                    }
                }
        }
        .tint(HassTokens.Ink.action)
        .onAppear { controller.clearError() }
    }

    private func pop() {
        if !path.isEmpty { path.removeLast() }
    }

    // MARK: - Overview

    private var overview: some View {
        let snapshot = controller.snapshot
        return List {
            if let error = controller.errorMessage {
                SprinklerAlert(text: error).listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            }
            Section {
                DynamicGridLayout(minCellWidth: minPillWidth, maxColumns: 4, spacing: HassTokens.Spacing.s) {
                    StatusPill(label: "Controller", value: format.status(snapshot),
                               symbol: snapshot.status == .watering ? SprinklerStyle.symbol : "info.circle",
                               tone: Self.tone(snapshot), surface: .groupedList)
                    StatusPill(label: "Battery", value: format.battery(snapshot), symbol: "battery.100percent",
                               tone: snapshot.batteryLow ? .warning : .neutral, surface: .groupedList)
                    StatusPill(label: "Next watering", value: format.nextStart(snapshot), symbol: "calendar.badge.clock", surface: .groupedList)
                    StatusPill(label: "Last watering", value: format.lastStart(snapshot.lastRun),
                               detail: snapshot.lastRun.runTimeMinutes.map(format.minutes), symbol: "clock.arrow.circlepath", surface: .groupedList)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } header: { SprinklerHeader("Status") }

            Section {
                ForEach(Array(snapshot.zones.enumerated()), id: \.offset) { index, zone in
                    let active = controller.activeValve == zone.config.valveEntityId
                    NavigationLink(value: SprinklerDetail.water(zone: index)) {
                        SprinklerRow(symbol: SprinklerStyle.symbol, isActive: active, title: zone.name,
                                     lines: [!zone.available ? "Unavailable" : active ? "Watering" : "Closed",
                                             format.lastStart(zone.lastRun)])
                    }
                    // Open while another zone waters (Water now explains and disables Start there): a disabled
                    // row dims its name below 4.5:1 and hides the zone's status from VoiceOver.
                    .disabled(!zone.available)
                    .accessibilityHint("Water now")
                    .accessibilityIdentifier("sprinkler.zone.\(index)")
                }
            } header: { SprinklerHeader("Zones") }

            Section {
                Button(role: .destructive) { controller.stopWatering() } label: {
                    Label("Stop watering", systemImage: "stop.circle")
                        .foregroundStyle(controller.isWatering ? HassTokens.Ink.danger : HassTokens.Ink.secondary)
                        .frame(minHeight: HassTokens.minTarget - 12)
                }
                .disabled(!controller.isWatering)
                .accessibilityIdentifier("sprinkler.stop")
            } header: { SprinklerHeader("Controls") }

            Section {
                Toggle(isOn: Binding(get: { controller.rainDelay }, set: { controller.setRainDelay($0) })) {
                    Label("Rain delay · 24 hours", systemImage: "cloud.heavyrain")
                }
                .accessibilityIdentifier("sprinkler.rainDelay")
                Toggle(isOn: Binding(get: { controller.smartWatering }, set: { controller.setSmartWatering($0) })) {
                    Label("Smart watering", systemImage: "wand.and.stars")
                }
                .accessibilityIdentifier("sprinkler.smartWatering")
            } header: { SprinklerHeader("Settings") }
            .disabled(!snapshot.available)

            Section {
                ForEach(Array(snapshot.zones.enumerated()), id: \.offset) { index, zone in
                    if let program = controller.program(index) {
                        ProgramRow(controller: controller, index: index, zoneName: zone.name, program: program, format: format)
                    }
                }
            } header: { SprinklerHeader("Schedule") }
        }
        .accessibilityIdentifier("sprinkler.overview")
    }

    static func tone(_ snapshot: SprinklerSnapshot) -> StatusPill.Tone {
        switch snapshot.status {
        case .unavailable: .unavailable
        case .fault: .danger
        case .watering: .active
        case .ready: snapshot.mode == "off" ? .warning : .ok
        }
    }
}

/// A program row: name, summary and details, opening its schedule; the switch enables or disables it.
struct ProgramRow: View {
    var controller: SprinklerController
    var index: Int
    var zoneName: String
    var program: SprinklerSnapshot.Program
    var format: SprinklerFormat

    var body: some View {
        let name = format.programName(zone: zoneName)
        HStack(spacing: HassTokens.Spacing.m) {
            NavigationLink(value: SprinklerDetail.schedule(zone: index)) {
                SprinklerRow(symbol: "calendar.badge.clock", isActive: program.enabled, title: name,
                             lines: [format.summary(program), format.details(program, zone: zoneName)])
            }
            .disabled(!program.available)
            .accessibilityIdentifier("sprinkler.program.\(index)")
            Toggle(name, isOn: Binding(get: { program.enabled }, set: { controller.setProgramEnabled(zone: index, $0) }))
                .labelsHidden()
                .disabled(!program.available)
                .accessibilityIdentifier("sprinkler.program.\(index).enabled")
        }
    }
}

/// An icon, a title and secondary lines.
struct SprinklerRow: View {
    var symbol: String
    var isActive: Bool
    var title: String
    var lines: [String]

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: HassTokens.Spacing.m) {
            Image(systemName: symbol)
                .foregroundStyle(isActive ? SprinklerStyle.water : HassTokens.Ink.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(HassTokens.Ink.primary)
                ForEach(lines, id: \.self) { line in
                    Text(line).font(.footnote).foregroundStyle(HassTokens.Ink.secondary)
                }
            }
        }
        .frame(minHeight: HassTokens.minTarget, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A section header drawn with the app's ink, so it keeps contrast on the grouped background.
struct SprinklerHeader: View {
    var title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(HassTokens.Ink.secondary)
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Water now

/// Water a zone for a chosen time (web `waterDetail`).
struct SprinklerWaterPage: View {
    var controller: SprinklerController
    var zone: Int
    var done: () -> Void
    @State private var minutes = SprinklersConfig.manualRunTime.default
    @State private var sending = false

    var body: some View {
        let snapshot = controller.snapshot
        let zoneState = snapshot.zones.indices.contains(zone) ? snapshot.zones[zone] : nil
        let enabled = controller.canStartWatering && (zoneState?.available ?? false) && !sending
        let range = SprinklersConfig.manualRunTime.min...SprinklersConfig.manualRunTime.max
        List {
            if let error = controller.errorMessage {
                SprinklerAlert(text: error).listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            }
            Section {
                Stepper(value: $minutes, in: range) {
                    StepperRow(title: "Run time", symbol: "timer", value: "\(minutes) min")
                }
                .accessibilityValue("\(minutes) minutes")
                .disabled(!controller.canStartWatering || !(zoneState?.available ?? false))
                .accessibilityIdentifier("sprinkler.runTime")
            } header: { SprinklerHeader("Water now · \(zoneState?.name ?? controller.config.title)") } footer: {
                if controller.isWatering {
                    Text("Another zone is watering. Stop it to water this one.")
                        .foregroundStyle(HassTokens.Ink.secondary)
                        .accessibilityIdentifier("sprinkler.waterBlocked")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                sending = true
                Task {
                    let ok = await controller.startWatering(zone: zone, minutes: minutes)
                    sending = false
                    if ok { done() }
                }
            } label: {
                Label("Start watering", systemImage: SprinklerStyle.symbol)
                    .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget - 16)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!enabled)
            .padding(HassTokens.Spacing.l)
            .background(.bar)
            .accessibilityIdentifier("sprinkler.startWatering")
        }
        .navigationTitle(zoneState?.name ?? controller.config.title)
        .inlineNavigationTitle()
        .onDisappear { controller.clearError() }
    }
}

// MARK: - Schedule

/// Edit a zone's program (web `scheduleDetail`): enabled, run now, days, start times and budget; Apply saves.
struct SprinklerSchedulePage: View {
    var controller: SprinklerController
    var zone: Int
    var done: () -> Void
    @State private var days: Set<Int>
    @State private var times: [Date]
    @State private var budget: Int
    @State private var sending = false
    private let format = SprinklerFormat()

    init(controller: SprinklerController, zone: Int, done: @escaping () -> Void) {
        self.controller = controller
        self.zone = zone
        self.done = done
        let program = controller.program(zone)
        _days = State(initialValue: Set(program?.days ?? []))
        let starts = (program?.startTimes.isEmpty ?? true) ? [SprinklersConfig.defaultStartTime] : program?.startTimes ?? []
        _times = State(initialValue: starts.compactMap { SprinklerFormat.date(clock: $0) })
        _budget = State(initialValue: program?.budget ?? 100)
    }

    var body: some View {
        let snapshot = controller.snapshot
        let program = controller.program(zone)
        let zoneName = snapshot.zones.indices.contains(zone) ? snapshot.zones[zone].name : controller.config.title
        let available = program?.available ?? false
        let enabled = program?.enabled ?? false
        List {
            if let error = controller.errorMessage {
                SprinklerAlert(text: error).listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            }
            Section {
                Toggle(isOn: Binding(get: { enabled }, set: { controller.setProgramEnabled(zone: zone, $0) })) {
                    Label("Program enabled", systemImage: "calendar.badge.checkmark")
                }
                .disabled(!available)
                .accessibilityIdentifier("sprinkler.schedule.enabled")
                Button { controller.startProgram(zone: zone) } label: {
                    // No fixed frame: a List row is already 44 pt tall and grows with the text (AX5 flagged clipping).
                    // Icon and text laid out by hand: the audit flagged the Label's title as clipping at AX5.
                    HStack(spacing: HassTokens.Spacing.m) {
                        Image(systemName: "play.fill")
                        Text("Start program")
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
                .disabled(!controller.canStartWatering || !enabled)
                // One name for the row (a hidden glyph read as unexposed text to the audit).
                .accessibilityLabel("Start program")
                .accessibilityIdentifier("sprinkler.schedule.start")
            }
            Section {
                DayPicker(days: $days).disabled(!available)
            } header: { SprinklerHeader("Days") }
            Section {
                ForEach(times.indices, id: \.self) { index in
                    HStack {
                        DatePicker("Start \(index + 1)", selection: $times[index], displayedComponents: .hourAndMinute)
                            .accessibilityIdentifier("sprinkler.schedule.time.\(index)")
                        Button(role: .destructive) { times.remove(at: index) } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.title3)
                                .frame(minWidth: HassTokens.minTarget, minHeight: HassTokens.minTarget)
                        }
                        .buttonStyle(.borderless)
                        .disabled(times.count <= 1)
                        .accessibilityLabel("Remove Start Time \(index + 1)")
                    }
                }
                Button {
                    times.append(SprinklerFormat.date(clock: SprinklersConfig.defaultStartTime) ?? .now)
                } label: {
                    Label("Add Another Start Time", systemImage: "plus")
                }
                .accessibilityIdentifier("sprinkler.schedule.addTime")
            } header: { SprinklerHeader("Start Times") }
            .disabled(!available)
            Section {
                Stepper(value: $budget, in: SprinklersConfig.budgetRange.min...SprinklersConfig.budgetRange.max,
                        step: SprinklersConfig.budgetRange.step) {
                    StepperRow(title: "Watering budget", symbol: "percent", value: "\(budget)%")
                }
                .accessibilityValue("\(budget) percent")
                .disabled(!available)
                .accessibilityIdentifier("sprinkler.schedule.budget")
            } footer: {
                Text("Run time · \(program?.runTimeMinutes ?? 0) min")
                    .font(.footnote)
                    .foregroundStyle(HassTokens.Ink.secondary)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                sending = true
                Task {
                    let ok = await controller.saveSchedule(
                        zone: zone, days: Array(days), startTimes: times.map { SprinklerFormat.clock(from: $0) }, budget: budget)
                    sending = false
                    if ok { done() }
                }
            } label: {
                Label("Apply", systemImage: "checkmark")
                    .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget - 16)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!available || days.isEmpty || times.isEmpty || sending)
            .padding(HassTokens.Spacing.l)
            .background(.bar)
            .accessibilityIdentifier("sprinkler.schedule.apply")
        }
        .navigationTitle(format.programName(zone: zoneName))
        .inlineNavigationTitle()
        .onDisappear { controller.clearError() }
    }
}

/// A stepper's label: icon and title, then the value. In `LabeledContent` the icon stacked above the title.
struct StepperRow: View {
    var title: String
    var symbol: String
    var value: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: HassTokens.Spacing.s) { label; Spacer(minLength: HassTokens.Spacing.s); valueText }
            VStack(alignment: .leading, spacing: 2) { label; valueText }
        }
    }

    private var label: some View {
        Label(title, systemImage: symbol).labelStyle(.titleAndIcon).foregroundStyle(HassTokens.Ink.primary)
    }

    private var valueText: some View {
        Text(value).monospacedDigit().foregroundStyle(HassTokens.Ink.primary)
    }
}

/// Seven day buttons, Sunday first; each reads its full name and whether it is selected.
struct DayPicker: View {
    @Binding var days: Set<Int>

    var body: some View {
        HStack(spacing: HassTokens.Spacing.xs) {
            ForEach(0..<7, id: \.self) { day in
                let on = days.contains(day)
                Button {
                    if on { days.remove(day) } else { days.insert(day) }
                } label: {
                    Text(SprinklerFormat.dayLetters[day])
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget)
                        .foregroundStyle(on ? Color.white : HassTokens.Ink.primary)
                        .background(on ? SprinklerStyle.water : Color.secondary.opacity(0.15), in: Circle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(SprinklerFormat.dayNames[day])
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("sprinkler.schedule.day.\(day)")
            }
        }
    }
}
