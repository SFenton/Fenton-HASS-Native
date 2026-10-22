import HassDesign
import HassTelemetry
import SwiftUI

/// Settings → Performance: what the telemetry has measured on this device, and an export for sharing
/// (pattern: `.agents/patterns/telemetry.md`).
///
/// HIG: [Lists and tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables) (grouped
/// list of labeled values) and [Activity views](https://developer.apple.com/design/human-interface-guidelines/activity-views)
/// (the export goes through the system share sheet).
public struct PerformanceScreen: View {
    @State private var report = PerformanceReport.current()
    @State private var recording = Telemetry.isEnabled
    @State private var exportURL: URL?

    /// Creates the screen.
    public init() {}

    public var body: some View {
        List {
            Section {
                Toggle("Record Telemetry", isOn: $recording)
                    .onChange(of: recording) { _, on in Telemetry.isEnabled = on }
                    .accessibilityIdentifier("performance.recording")
            } footer: {
                FormFooter("Measures scrolling, navigation, loading, live updates and images on this device. Nothing leaves the device unless you export it.")
            }

            Section {
                if report.scroll.isEmpty {
                    emptyRow("Scroll a page to measure it.")
                }
                ForEach(report.scroll) { row in
                    PerformanceRow(
                        title: row.page,
                        value: String(format: "%.1f ms/s", row.stats.hitchRatio),
                        detail: "\(row.stats.hitches) hitches in \(row.stats.frames) frames · worst \(Int(row.stats.worstFrameMs)) ms",
                        tone: row.stats.hitchRatio < 5 ? .good : row.stats.hitchRatio < 10 ? .warning : .bad
                    )
                }
                if let ratio = report.metricKitHitchRatio {
                    PerformanceRow(title: "MetricKit (last day)", value: String(format: "%.1f ms/s", ratio),
                                   detail: "System scroll hitch ratio", tone: ratio < 5 ? .good : ratio < 10 ? .warning : .bad)
                }
            } header: { FormHeader("Scrolling") }

            Section {
                if report.pages.isEmpty { emptyRow("No page has waited for content yet.") }
                ForEach(report.pages) { page in
                    statsRow(page.name, page.stats)
                }
                PerformanceRow(title: "Shown instantly", value: "\(report.counter("gate.instant"))",
                               detail: "Pages whose data was already there")
            } header: { FormHeader("Page Loading") }

            Section {
                if report.navigation.isEmpty {
                    emptyRow("Switch tabs and open pages to measure them.")
                        .accessibilityIdentifier("performance.navigation.empty")
                }
                ForEach(report.navigation) { row in
                    PerformanceRow(title: row.surface.title, value: Self.navigationValue(row),
                                   detail: Self.navigationDetail(row), tone: Self.navigationTone(row))
                        .accessibilityIdentifier("performance.navigation.\(row.surface.rawValue)")
                }
            } header: { FormHeader("Navigation") }

            Section {
                if let stats = report.stats["EntityUpdate"] { statsRow("Apply time", stats) }
                PerformanceRow(title: "Deliveries", value: "\(report.counter("entity.deliveries"))",
                               detail: "\(report.counter("entity.changed")) entity changes")
            } header: { FormHeader("Live Updates") }

            Section {
                if let stats = report.stats["ServiceCall"] { statsRow("Service call", stats) }
                if let stats = report.stats["OptimisticConfirm"] { statsRow("Confirmed by Home Assistant", stats) }
                PerformanceRow(title: "Rolled back", value: "\(report.counter("optimistic.rollbacks"))",
                               detail: "Optimistic values undone by failed calls")
            } header: { FormHeader("Actions") }

            Section {
                PerformanceRow(title: "Cache hits", value: "\(report.counter("image.memoryHits") + report.counter("image.diskHits"))",
                               detail: "\(report.counter("image.memoryHits")) memory · \(report.counter("image.diskHits")) disk")
                PerformanceRow(title: "Downloads", value: "\(report.counter("image.fetches") + report.counter("image.changed"))",
                               detail: "\(report.counter("image.notModified")) unchanged (304) · \(report.counter("image.failures")) failed")
                if let stats = report.stats["ImageDecode"] { statsRow("Decode", stats) }
                PerformanceRow(title: "On disk", value: ByteCountFormatter.string(fromByteCount: Int64(report.diskBytes), countStyle: .file),
                               detail: "\(report.diskFiles) images")
                Button("Clear Image Cache", role: .destructive) {
                    ImagePipeline.shared.removeAll()
                    refresh()
                }
                .accessibilityIdentifier("performance.clearImages")
            } header: {
                Text("Images")
            }

            Section {
                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label("Export Telemetry", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("performance.export")
                }
                Button("Reset Measurements", role: .destructive) {
                    Telemetry.log.reset()
                    refresh()
                }
                .accessibilityIdentifier("performance.reset")
            } footer: {
                FormFooter("\(report.recordCount) samples · \(report.metricKitPayloads) MetricKit reports")
            }
        }
        .navigationTitle("Performance")
        .refreshable { refresh() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh", systemImage: "arrow.clockwise") { refresh() }
                    .accessibilityIdentifier("performance.refresh")
            }
        }
        .task { refresh() }
        .accessibilityIdentifier("performance.screen")
    }

    /// The headline: the median time to settle (or to the first frame when the transition has no end of its own).
    static func navigationValue(_ row: NavigationTelemetry.Row) -> String {
        let headline = row.settled ?? row.firstFrame
        return headline.map { String(format: "%.0f ms", $0.p50) } ?? "-"
    }

    /// p50 and p95 for each phase, and the main thread's worst turn.
    static func navigationDetail(_ row: NavigationTelemetry.Row) -> String {
        func pair(_ label: String, _ stats: TelemetryStats?) -> String? {
            stats.map { String(format: "%@ p50 %.0f · p95 %.0f ms", label, $0.p50, $0.p95) }
        }
        var parts = [pair("first frame", row.firstFrame), pair("settled", row.settled)].compactMap { $0 }
        if let worst = row.turnWorst { parts.append(String(format: "worst turn %.0f ms", worst.max)) }
        parts.append("\(row.count) samples")
        return parts.joined(separator: " · ")
    }

    /// A turn over a 120 Hz frame (8 ms) at the 95th percentile is a dropped frame during the transition.
    static func navigationTone(_ row: NavigationTelemetry.Row) -> PerformanceRow.Tone {
        guard let p95 = row.turnP95?.p95 else { return .neutral }
        return p95 <= 8 ? .good : p95 <= 16 ? .warning : .bad
    }

    private func refresh() {
        report = PerformanceReport.current()
        exportURL = try? PerformanceReport.writeExport()
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text).foregroundStyle(HassTokens.Ink.secondary)
    }

    private func statsRow(_ title: String, _ stats: TelemetryStats) -> some View {
        PerformanceRow(title: title, value: String(format: "%.0f ms", stats.p50),
                       detail: String(format: "median · p95 %.0f ms · max %.0f ms · %d samples", stats.p95, stats.max, stats.count))
    }
}
