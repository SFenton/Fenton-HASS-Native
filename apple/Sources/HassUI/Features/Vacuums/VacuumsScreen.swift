import HassCore
import HassDesign
import SwiftUI

/// The Vacuums page on the app's connection (spec: `.agents/pages/vacuums/spec.md`; web `VacuumPage`).
struct VacuumsScreen: View {
    @Environment(HassConnection.self) private var connection

    var body: some View {
        VacuumsPage(store: connection.store, caller: connection) { vacuum in
            VacuumSheet(vacuum: vacuum, connection: connection)
        }
    }
}

/// Robot Vacuums and Auto-Clean on the wallpaper (direction G, mockup n6-vacuums): a one-line summary under the large
/// title, the robots as `.cleaning` tiles, and Auto-Clean as an inset list of switches. One column on phones, folded or
/// portrait; where a split is allowed (unfolded Duo and iPad in landscape) Robot Vacuums leads and Auto-Clean sits
/// beside it.
struct VacuumsPage<Sheet: View>: View {
    @State private var autoClean: VacuumAutoCleanController
    @State private var open: VacuumConfig?
    private let store: EntityStore
    private let sheet: (VacuumConfig) -> Sheet
    @Environment(\.horizontalSizeClass) private var sizeClass
    @ScaledMetric(relativeTo: .subheadline) private var minTileWidth: CGFloat = 150

    /// Creates the page.
    /// - Parameters:
    ///   - initialVacuum: A vacuum whose sheet opens at once (gallery).
    ///   - sheet: Builds a vacuum's sheet.
    init(store: EntityStore, caller: any HassServiceCalling, scheduler: any RevertScheduler = TaskRevertScheduler(),
         initialVacuum: VacuumConfig? = nil, @ViewBuilder sheet: @escaping (VacuumConfig) -> Sheet) {
        self.store = store
        self.sheet = sheet
        _autoClean = State(initialValue: VacuumAutoCleanController(store: store, caller: caller, scheduler: scheduler))
        _open = State(initialValue: initialVacuum)
    }

    var body: some View {
        GeometryReader { proxy in
            let split = SplitPolicy.allowsSplit(size: proxy.size, isRegularWidth: sizeClass == .regular)
            Group {
                if split {
                    HStack(alignment: .top, spacing: 0) {
                        ScrollView { robotsColumn.padding([.horizontal, .bottom], HassTokens.Spacing.l) }
                        .frame(width: SplitPolicy.dividerX(width: proxy.size.width, hingeMidX: nil))
                        Divider().overlay(HassTokens.Surface.separator)
                        ScrollView { autoCleanSection.padding([.horizontal, .bottom], HassTokens.Spacing.l) }
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: HassTokens.Spacing.xl) {
                            robotsColumn
                            autoCleanSection
                        }
                        .padding([.horizontal, .bottom], HassTokens.Spacing.l)
                    }
                }
            }
            .scrollTelemetry("Vacuums")
            .accessibilityIdentifier(split ? "vacuums.layout.split" : "vacuums.layout.single")
        }
        .navigationTitle("Vacuums")
        .sheet(item: $open) { vacuum in
            sheet(vacuum).hassSheet(.page)
        }
    }

    /// The summary line and Robot Vacuums: the page's first column.
    private var robotsColumn: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.m) {
            summary
            vacuumsSection
        }
    }

    // MARK: - Summary

    /// "1 Cleaning · 1 Needs Attention" under the large title (mockup n6-vacuums), or nothing when no robot reports.
    @ViewBuilder
    private var summary: some View {
        if let line = VacuumPageFormat.summary(states: Vacuums.all.map { store.entity($0.entityId).state?.state }) {
            Text(line)
                .font(.subheadline)
                .monospacedDigit()
                // Straight on the wallpaper, which is always dark-styled: 72% label ink measured 4.0:1 ("1 Cleaning", iPhone,
                // 2026-10-16), so use the always-dark secondary at 85%.
                .foregroundStyle(HassTokens.Ink.onDarkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("vacuums.summary")
        }
    }

    // MARK: - Robot Vacuums

    private var vacuumsSection: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
            PageSectionHeader("Robot Vacuums")
            DynamicGridLayout(minCellWidth: minTileWidth, maxColumns: 6, equalRowHeights: true) {
                ForEach(Vacuums.all) { vacuum in
                    let tile = VacuumPageFormat.tile(
                        state: store.entity(vacuum.entityId).state?.state,
                        battery: store.entity(vacuum.batteryEntityId).state?.state,
                        error: store.entity(vacuum.errorEntityId).state?.state
                    )
                    GlassTile(
                        title: vacuum.title,
                        subtitle: tile.subtitle,
                        symbol: VacuumStyle.symbol(tile.icon),
                        family: .cleaning,
                        isActive: tile.isActive,
                        isError: tile.isError,
                        kind: .navigate,
                        progress: tile.progress
                    ) { open = vacuum }
                    .accessibilityHint("Opens the vacuum controls and map.")
                    .accessibilityIdentifier("vacuums.tile.\(vacuum.vacuumMapId)")
                }
            }
            .equalHeightTiles()
        }
    }

    // MARK: - Auto-Clean

    private var autoCleanSection: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
            PageSectionHeader("Auto-Clean")
            ModuleList {
                ForEach(Vacuums.autoCleanControls) { control in
                    autoCleanRow(control)
                }
            }
        }
    }

    /// One automation as a switch row: "Main Floor", "Enabled" or "Paused".
    private func autoCleanRow(_ control: Vacuums.AutoCleanControl) -> some View {
        let display = autoClean.display(control)
        return ModuleRow(
            control.title,
            subtitle: display.subtitle,
            symbol: "clock.arrow.circlepath",
            glyph: ColorFamily.cleaning.glyph,
            // Unavailable rows dim only the glyph; their text keeps full contrast.
            glyphOpacity: display.isUnavailable ? 0.4 : 1
        ) {
            Toggle(control.title, isOn: Binding(
                get: { autoClean.display(control).isEnabled },
                set: { _ in autoClean.toggle(control) }
            ))
            .labelsHidden()
            .disabled(display.isUnavailable)
            .accessibilityHint("Turns automatic cleaning on or off.")
            .accessibilityIdentifier("vacuums.autoClean.\(control.entityId)")
        }
    }
}

// MARK: - Format

/// What the Vacuums page says about its robots, kept apart from the generic page so tests can call it.
enum VacuumPageFormat {
    /// The page summary from the robots' states: counts of cleaning, returning and errored robots ("Needs
    /// Attention"), "All Docked" when every robot is docked, or nil when there is nothing to say.
    static func summary(states: [String?]) -> String? {
        let normalized = states.map { $0?.trimmingCharacters(in: .whitespaces).lowercased() ?? "" }
        let parts = [("cleaning", "Cleaning"), ("returning", "Returning"), ("error", "Needs Attention")].compactMap { state, label in
            let count = normalized.count(where: { $0 == state })
            return count > 0 ? "\(count) \(label)" : nil
        }
        if !parts.isEmpty { return parts.joined(separator: " · ") }
        if !normalized.isEmpty, normalized.allSatisfy({ $0 == "docked" }) { return "All Docked" }
        return nil
    }

    /// What a robot's tile draws.
    struct TileFace: Equatable {
        var subtitle: String
        var icon: String
        var isActive: Bool
        var isError: Bool
        /// The battery band while cleaning; nil otherwise.
        var progress: Double?
    }

    /// A robot's tile: filled while it works (cleaning, returning, paused), off when docked or idle, and the error
    /// face with the reported issue appended ("Error • 23% • Wheel Stuck").
    static func tile(state: String?, battery: String?, error: String?) -> TileFace {
        let visual = VacuumVisual.state(state)
        let isError = visual.tone == .danger
        var subtitle = VacuumFormat.tileSubtitle(state: state, battery: battery)
        let issue = VacuumStatusResolver.nativeIssue(error)
        if isError, issue.status == .present, let code = issue.code, !code.isEmpty {
            subtitle += " • \(StateText.titleCase(code))"
        }
        let isCleaning = state?.trimmingCharacters(in: .whitespaces).lowercased() == "cleaning"
        let level = battery.flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }.map { min(max($0 / 100, 0), 1) }
        return TileFace(
            subtitle: subtitle,
            icon: visual.icon,
            isActive: [.active, .returning, .warning].contains(visual.tone),
            isError: isError,
            progress: isCleaning ? level : nil
        )
    }
}
