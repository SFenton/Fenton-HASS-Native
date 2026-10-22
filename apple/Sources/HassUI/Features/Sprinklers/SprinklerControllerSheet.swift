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
                .modalChrome()
                .navigationTitle(controller.config.title)
                .sheetSubtitle(format.subtitle(controller.snapshot))
                .inlineNavigationTitle()
                .toolbar { SheetCloseItem { dismiss() } }
                .navigationDestination(for: SprinklerDetail.self) { detail in
                    Group {
                        switch detail {
                        case let .water(zone): SprinklerWaterPage(controller: controller, zone: zone) { pop() }
                        case let .schedule(zone): SprinklerSchedulePage(controller: controller, zone: zone) { pop() }
                        }
                    }
                    .modalChrome()
                    // Close on every level, so the sheet closes from a pushed page too (HIG: Sheets).
                    .toolbar { SheetCloseItem { dismiss() } }
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
                InlineAlert(error).listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            }
            Section {
                DynamicGridLayout(minCellWidth: minPillWidth, maxColumns: 4, spacing: HassTokens.Spacing.s) {
                    StatusPill(label: "Controller", value: format.status(snapshot),
                               symbol: snapshot.status == .watering ? SprinklerStyle.symbol : "info.circle",
                               tone: Self.tone(snapshot), surface: .groupedList)
                    StatusPill(label: "Battery", value: format.battery(snapshot), symbol: "battery.100percent",
                               tone: snapshot.batteryLow ? .warning : .neutral, surface: .groupedList)
                    StatusPill(label: "Next Watering", value: format.nextStart(snapshot), symbol: "calendar.badge.clock", surface: .groupedList)
                    StatusPill(label: "Last Watering", value: format.lastStart(snapshot.lastRun),
                               detail: snapshot.lastRun.runTimeMinutes.map(format.minutes), symbol: "clock.arrow.circlepath", surface: .groupedList)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } header: { FormHeader("Status") }

            Section {
                ForEach(Array(snapshot.zones.enumerated()), id: \.element.config.valveEntityId) { index, zone in
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
            } header: { FormHeader("Zones") }

            Section {
                Button(role: .destructive) { controller.stopWatering() } label: {
                    WrappingRowLabel(title: "Stop Watering", symbol: "stop.circle")
                        .foregroundStyle(controller.isWatering ? HassTokens.Ink.danger : HassTokens.Ink.secondary)
                }
                .accessibilityLabel("Stop Watering")
                .disabled(!controller.isWatering)
                .accessibilityIdentifier("sprinkler.stop")
            } header: { FormHeader("Controls") }

            Section {
                Toggle(isOn: Binding(get: { controller.rainDelay }, set: { controller.setRainDelay($0) })) {
                    Label("Rain Delay · 24 Hours", systemImage: "cloud.heavyrain")
                }
                .accessibilityIdentifier("sprinkler.rainDelay")
                Toggle(isOn: Binding(get: { controller.smartWatering }, set: { controller.setSmartWatering($0) })) {
                    Label("Smart Watering", systemImage: "wand.and.stars")
                }
                .accessibilityIdentifier("sprinkler.smartWatering")
            } header: { FormHeader("Settings") }
            .disabled(!snapshot.available)

            Section {
                // Zones without a program are left out before the ForEach, so every row is one ProgramRow.
                ForEach(programRows(snapshot), id: \.zone.config.valveEntityId) { row in
                    ProgramRow(controller: controller, index: row.index, zoneName: row.zone.name, program: row.program, format: format)
                }
            } header: { FormHeader("Schedule") }
        }
        .accessibilityIdentifier("sprinkler.overview")
    }

    /// The Schedule section's rows: zones that have a program, keeping each zone's index.
    private func programRows(_ snapshot: SprinklerSnapshot) -> [(index: Int, zone: SprinklerSnapshot.Zone, program: SprinklerSnapshot.Program)] {
        snapshot.zones.indices.compactMap { index in
            controller.program(index).map { (index: index, zone: snapshot.zones[index], program: $0) }
        }
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
                .stateForeground("SprinklerRow", isActive ? SprinklerStyle.water : HassTokens.Ink.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(HassTokens.Ink.primary)
                // A watering zone's state reads in the water colour (`#4CC9F0` on the sheet cell is 8:1).
                Text(lines.joined(separator: " · "))
                    .font(.subheadline)
                    .stateForeground("SprinklerRow", isActive ? SprinklerStyle.water : HassTokens.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(minHeight: HassTokens.minTarget, alignment: .leading)
        .accessibilityElement(children: .combine)
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
                InlineAlert(error).listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            }
            Section {
                Stepper(value: $minutes, in: range) {
                    StepperRow(title: "Run Time", symbol: "timer", value: "\(minutes) min")
                }
                .accessibilityValue("\(minutes) minutes")
                .disabled(!controller.canStartWatering || !(zoneState?.available ?? false))
                .accessibilityIdentifier("sprinkler.runTime")
            } header: { FormHeader("Water Now") } footer: {
                if controller.isWatering {
                    FormFooter("Another zone is watering. Stop it to water this one.")
                        .accessibilityIdentifier("sprinkler.waterBlocked")
                } else {
                    FormFooter("Waters \(zoneState?.name ?? controller.config.title) once, for \(range.lowerBound) to \(range.upperBound) minutes. The schedule is not changed.")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            // The one primary action, in the owner's water colour with dark text (direction G, Primary buttons).
            PrimaryButton("Start Watering", systemImage: SprinklerStyle.symbol, family: .water) {
                sending = true
                Task {
                    let ok = await controller.startWatering(zone: zone, minutes: minutes)
                    sending = false
                    if ok { done() }
                }
            }
            .disabled(!enabled)
            .accessibilityIdentifier("sprinkler.startWatering")
            .padding(HassTokens.Spacing.l)
            .background(.bar)
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
    @State private var times: [StartTime]
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
        _times = State(initialValue: starts.compactMap { SprinklerFormat.date(clock: $0) }.map(StartTime.init))
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
                InlineAlert(error).listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            }
            Section {
                Toggle(isOn: Binding(get: { enabled }, set: { controller.setProgramEnabled(zone: zone, $0) })) {
                    Label("Program Enabled", systemImage: "calendar.badge.checkmark")
                }
                .disabled(!available)
                .accessibilityIdentifier("sprinkler.schedule.enabled")
                Button { controller.startProgram(zone: zone) } label: {
                    // No fixed frame: a List row is already 44 pt tall and grows with the text (AX5 flagged clipping).
                    WrappingRowLabel(title: "Start Program Now", symbol: "play.fill")
                }
                .disabled(!controller.canStartWatering || !enabled)
                // One name for the row (a hidden glyph read as unexposed text to the audit).
                .accessibilityLabel("Start Program Now")
                .accessibilityIdentifier("sprinkler.schedule.start")
            }
            Section {
                DayPicker(days: $days).disabled(!available)
            } header: { FormHeader("Days") }
            Section {
                // Rows are identified by their own id, not their position, so removing one keeps the others' pickers.
                ForEach(Array(times.enumerated()), id: \.element.id) { index, time in
                    HStack {
                        DatePicker("Start \(index + 1)", selection: binding(for: time.id), displayedComponents: .hourAndMinute)
                            .accessibilityIdentifier("sprinkler.schedule.time.\(index)")
                        Button(role: .destructive) { remove(time.id) } label: {
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
                    times.append(StartTime(SprinklerFormat.date(clock: SprinklersConfig.defaultStartTime) ?? .now))
                } label: {
                    WrappingRowLabel(title: "Add Another Start Time", symbol: "plus")
                }
                .accessibilityLabel("Add Another Start Time")
                .accessibilityIdentifier("sprinkler.schedule.addTime")
            } header: { FormHeader("Start Times") }
            .disabled(!available)
            Section {
                Stepper(value: $budget, in: SprinklersConfig.budgetRange.min...SprinklersConfig.budgetRange.max,
                        step: SprinklersConfig.budgetRange.step) {
                    StepperRow(title: "Watering Budget", symbol: "percent", value: "\(budget)%")
                }
                .accessibilityValue("\(budget) percent")
                .disabled(!available)
                .accessibilityIdentifier("sprinkler.schedule.budget")
            } footer: {
                FormFooter("Run Time · \(program?.runTimeMinutes ?? 0) min")
            }
        }
        .safeAreaInset(edge: .bottom) {
            PrimaryButton("Apply", systemImage: "checkmark", family: .water) {
                sending = true
                Task {
                    let ok = await controller.saveSchedule(
                        zone: zone, days: Array(days), startTimes: times.map { SprinklerFormat.clock(from: $0.date) }, budget: budget)
                    sending = false
                    if ok { done() }
                }
            }
            .disabled(!available || days.isEmpty || times.isEmpty || sending)
            .accessibilityIdentifier("sprinkler.schedule.apply")
            .padding(HassTokens.Spacing.l)
            .background(.bar)
        }
        .navigationTitle(format.programName(zone: zoneName))
        .sheetSubtitle(program.map(format.summary))
        .inlineNavigationTitle()
        .onDisappear { controller.clearError() }
    }

    // MARK: - Start times

    /// One editable start time. Its id is allocated once, so a row keeps its identity when another is removed.
    struct StartTime: Identifiable, Equatable {
        let id = UUID()
        var date: Date

        init(_ date: Date) { self.date = date }
    }

    private func binding(for id: StartTime.ID) -> Binding<Date> {
        Binding {
            times.first { $0.id == id }?.date ?? .now
        } set: { date in
            guard let index = times.firstIndex(where: { $0.id == id }) else { return }
            times[index].date = date
        }
    }

    private func remove(_ id: StartTime.ID) {
        times.removeAll { $0.id == id }
    }
}

/// A list button's icon and title, laid out by hand so the title wraps: the audit flagged a `Label` title in
/// a list button as clipping at large text sizes (Start program, Add Another Start Time).
struct WrappingRowLabel: View {
    var title: String
    var symbol: String

    var body: some View {
        HStack(spacing: HassTokens.Spacing.m) {
            Image(systemName: symbol)
            Text(title)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
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
        // One row when seven 44 pt buttons fit; else Sunday-Wednesday over Thursday-Saturday (the folded iPhone
        // Duo's row left 42 pt each).
        ViewThatFits(in: .horizontal) {
            HStack(spacing: HassTokens.Spacing.xs) { buttons(0..<7) }
            // Two rows on a shared four-column grid, so Thursday-Saturday line up under Sunday-Tuesday.
            Grid(horizontalSpacing: HassTokens.Spacing.xs, verticalSpacing: HassTokens.Spacing.s) {
                GridRow { buttons(0..<4) }
                GridRow { buttons(4..<7) }
            }
        }
    }

    @ViewBuilder
    private func buttons(_ range: Range<Int>) -> some View {
        ForEach(range, id: \.self) { day in
            let on = days.contains(day)
            Button {
                if on { days.remove(day) } else { days.insert(day) }
            } label: {
                Text(SprinklerFormat.dayLetters[day])
                    .font(.subheadline.weight(.semibold))
                    .frame(minWidth: HassTokens.minTarget, maxWidth: .infinity, minHeight: HassTokens.minTarget)
                    // Chosen days fill with the water colour and dark text, as the primary button (direction G).
                    .stateForeground("DayPicker", on ? HassTokens.Surface.sheetGround : HassTokens.Ink.primary)
                    .background {
                        Circle().fill(on ? SprinklerStyle.water : Color.secondary.opacity(0.15))
                            .stateColorTransition("DayPicker", value: on)
                    }
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(SprinklerFormat.dayNames[day])
            .accessibilityAddTraits(on ? .isSelected : [])
            .accessibilityIdentifier("sprinkler.schedule.day.\(day)")
        }
    }
}
