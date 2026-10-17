#if DEBUG
import HassCore
import HassDesign
import HassTelemetry
import SwiftUI

/// Debug gallery for the performance pieces (`FENTON_GALLERY=performance`), chosen with `FENTON_GALLERY_PERF`:
/// - `screen` (default): ``PerformanceScreen`` over seeded measurements.
/// - `gate`: a ``ContentGate`` whose data loads after a delay (`FENTON_GALLERY_GATE_DELAY_MS`), with a Reload button.
/// - `grid`: 300 glass tiles in a ``DynamicGridLayout``, a fixed workload for the fast-scroll tests.
/// - `chips`: Home's six-chip ``StatusRail`` over a column of tiles on fixture state, for the sideways-swipe tests.
struct PerformanceGallery: View {
    private var mode: String { ProcessInfo.processInfo.environment["FENTON_GALLERY_PERF"] ?? "screen" }

    var body: some View {
        switch mode {
        case "gate": GateDemo()
        case "grid": GridWorkload()
        case "chips": ChipRailWorkload()
        default:
            // Seeded before the screen is built, once per process: the screen reads the log when it appears, and seeding
            // from `onAppear` ran after that read, leaving every section empty (journeys saw "Scroll a page to measure
            // it", 2026-10-17). Reset Measurements must stay reset, hence once.
            let _ = Self.seeded
            PerformanceScreen()
        }
    }

    private static let seeded: Void = seed()

    /// Fills the log with representative samples so the screen shows every section.
    static func seed() {
        Telemetry.isEnabled = true
        let log = Telemetry.log
        log.reset()
        log.addScroll(page: "Recipes", frameMs: Array(repeating: 8.3, count: 240) + [33, 41, 25], budgetMs: 8.33)
        log.addScroll(page: "Room · Living Room", frameMs: Array(repeating: 8.3, count: 300) + [12], budgetMs: 8.33)
        for ms in [120.0, 180, 240, 420] {
            log.record(TelemetryRecord(kind: "\(Telemetry.Name.contentReady)", page: "Recipes", durationMs: ms))
        }
        for ms in [0.4, 0.6, 1.1, 3.2] { log.record(TelemetryRecord(kind: "\(Telemetry.Name.entityUpdate)", durationMs: ms)) }
        for ms in [80.0, 95, 140] { log.record(TelemetryRecord(kind: "\(Telemetry.Name.serviceCall)", durationMs: ms)) }
        for ms in [210.0, 380, 650] { log.record(TelemetryRecord(kind: "\(Telemetry.Name.optimisticConfirm)", durationMs: ms)) }
        for ms in [2.0, 3.5, 9.0] { log.record(TelemetryRecord(kind: "\(Telemetry.Name.imageDecode)", durationMs: ms)) }
        for (counter, value) in ["gate.instant": 12, "entity.deliveries": 640, "entity.changed": 910, "optimistic.rollbacks": 1,
                                 "image.memoryHits": 230, "image.diskHits": 41, "image.fetches": 18, "image.notModified": 7] {
            log.increment(counter, by: value)
        }
    }
}

/// A gated page whose data arrives after a delay; Reload fades it out and back in.
///
/// `FENTON_GALLERY_GATE_DELAY_MS=<ms>` sets the delay (default 900). The simulator's launch alone can outlast the
/// default, so a journey that watches the spinner stretches it (`PerformanceJourneyTests`).
private struct GateDemo: View {
    @State private var loaded = false
    @State private var generation = 0

    private static var loadDelay: Duration {
        .milliseconds(ProcessInfo.processInfo.environment["FENTON_GALLERY_GATE_DELAY_MS"].flatMap { Int($0) } ?? 900)
    }

    var body: some View {
        ContentGate(page: "Gallery Gate", isReady: loaded) {
            ScrollView {
                VStack(alignment: .leading, spacing: HassTokens.Spacing.m) {
                    ForEach(0..<8) { index in
                        GlassTile(title: "Item \(index + 1)", subtitle: "Loaded \(generation)", symbol: "square.grid.2x2",
                                  tint: HassTokens.Tint.light, isActive: index.isMultiple(of: 2)) {}
                    }
                }
                .padding()
            }
            .accessibilityIdentifier("gate.content")
        }
        .navigationTitle("Content Gate")
        .toolbar {
            Button("Reload") {
                loaded = false
                generation += 1
            }
            .accessibilityIdentifier("gate.reload")
        }
        .task(id: generation) {
            try? await Task.sleep(for: Self.loadDelay)
            loaded = true
        }
    }
}

/// A long tile grid that the fast-scroll tests flick through.
private struct GridWorkload: View {
    var body: some View {
        ScrollView {
            DynamicGridLayout(minCellWidth: 150, maxColumns: 6) {
                ForEach(0..<300) { index in
                    GlassTile(title: "Tile \(index + 1)", subtitle: index.isMultiple(of: 3) ? "On" : "Off",
                              symbol: "lightbulb", tint: HassTokens.Tint.light, isActive: index.isMultiple(of: 3)) {}
                }
            }
            .padding()
        }
        .scrollTelemetry("Gallery Grid")
        .accessibilityIdentifier("perf.grid")
        .navigationTitle("Grid Workload")
    }
}

/// Home's status rail over a page of tiles, on fixture state: the sideways-swipe test flicks the rail
/// (`FastScrollPerformanceTests.testSwipeChipRail`). The page is deliberately busy, because a nested scroll's cost
/// grows with the page around it (`.agents/patterns/status-rail.md`, Scrolling). Lights alternate on and off so
/// every chip draws its fill.
private struct ChipRailWorkload: View {
    @State private var store: EntityStore

    init() {
        let store = EntityStore()
        store.replaceAll(Self.states, freshness: .live)
        _store = State(initialValue: store)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HassTokens.Spacing.xl) {
                StatusRail { _ in }
                DynamicGridLayout(minCellWidth: 150, maxColumns: 2) {
                    ForEach(0..<120) { index in
                        GlassTile(title: "Tile \(index + 1)", subtitle: index.isMultiple(of: 3) ? "On" : "Off",
                                  symbol: "lightbulb", tint: HassTokens.Tint.light, isActive: index.isMultiple(of: 3)) {}
                    }
                }
                .padding(.horizontal, HassTokens.Spacing.l)
            }
            .padding(.vertical, HassTokens.Spacing.m)
        }
        .scrollTelemetry("Gallery Chips")
        .accessibilityIdentifier("perf.chips")
        .navigationTitle("Chip Rail Workload")
        .environment(store)
    }

    private static var states: [EntityState] {
        var states = RoomOverview.lightEntityIds.enumerated().map {
            EntityState(entityId: $1, state: $0.isMultiple(of: 3) ? "on" : "off")
        }
        states += RoomOverview.contactEntityIds.enumerated().map {
            EntityState(entityId: $1, state: $0 == 0 ? "on" : "off")
        }
        states += [
            EntityState(entityId: SecurityConfig.alarmEntityId, state: "armed_home"),
            EntityState(entityId: "input_text.all_climate_range", state: "70.0 - 72.4°F"),
            EntityState(entityId: "binary_sensor.occupancy_sensors", state: "on"),
            EntityState(entityId: "input_text.all_aqi_range", state: "21 - 34"),
            EntityState(entityId: "input_text.all_pm25_range", state: "4 - 9"),
        ]
        return states
    }
}
#endif
