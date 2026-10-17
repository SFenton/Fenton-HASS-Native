#if os(macOS)
import AppKit
import Foundation
import HassDesign
import HassTelemetry
@testable import HassUI
import SwiftUI
import Testing

/// The Performance screen and what feeds it: the report built from the telemetry log, MetricKit's saved payloads,
/// the scroll frame monitor and the export file.
@MainActor
@Suite(.serialized)
struct PerformanceDiagnosticsTests {
    static let phone = CGSize(width: 402, height: 874)

    /// A MetricKit collector and image pipeline writing to private folders.
    func isolated() -> (MetricKitCollector, ImagePipeline, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("perf-\(UUID().uuidString)", isDirectory: true)
        return (MetricKitCollector(directory: folder.appendingPathComponent("metrickit")),
                ImagePipeline(directory: folder.appendingPathComponent("images")), folder)
    }

    // MARK: Report

    @Test func theReportRanksPagesAndSummarisesTheLog() {
        let (metricKit, pipeline, folder) = isolated()
        defer { try? FileManager.default.removeItem(at: folder) }
        let log = TelemetryLog(capacity: 50)
        log.addScroll(page: "Calm", frameMs: Array(repeating: 8.3, count: 100), budgetMs: 8.33)
        log.addScroll(page: "Janky", frameMs: Array(repeating: 8.3, count: 60) + [40, 50], budgetMs: 8.33)
        for ms in [100.0, 300] { log.record(TelemetryRecord(kind: "ContentReady", page: "Slow Page", durationMs: ms)) }
        log.record(TelemetryRecord(kind: "ContentReady", page: "Quick Page", durationMs: 20))
        log.record(TelemetryRecord(kind: "ServiceCall", durationMs: 90))
        log.increment("gate.instant", by: 3)
        metricKit.store(Data(#"{"metrics":{"scrollHitchTimeRatio":"2.5 ms per s"}}"#.utf8), kind: "metrics")

        let report = PerformanceReport.current(log: log, pipeline: pipeline, metricKit: metricKit)
        #expect(report.scroll.map(\.page) == ["Janky", "Calm"], "worst hitch ratio first")
        #expect(report.pages.map(\.name) == ["Slow Page", "Quick Page"], "slowest median first")
        #expect(report.counter("gate.instant") == 3 && report.counter("missing") == 0)
        #expect(report.stats["ServiceCall"]?.count == 1)
        #expect(report.recordCount == 4)
        #expect(report.metricKitPayloads == 1)
        #expect(report.metricKitHitchRatio == 2.5)
        #expect(report.diskFiles == 0 && report.diskBytes == 0)
    }

    @Test func theExportHoldsTelemetryAndMetricKitPayloads() throws {
        let (metricKit, _, folder) = isolated()
        defer { try? FileManager.default.removeItem(at: folder) }
        let log = TelemetryLog()
        log.record(TelemetryRecord(kind: "EntityUpdate", durationMs: 1.5))
        log.increment("entity.deliveries")
        metricKit.store(Data(#"{"diagnostics":{"hangs":1}}"#.utf8), kind: "diagnostics")
        let url = try PerformanceReport.writeExport(log: log, metricKit: metricKit)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(url.lastPathComponent.hasPrefix("FentonHome-telemetry-") && url.pathExtension == "json")
        let object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let telemetry = try #require(object["telemetry"] as? [String: Any])
        #expect((telemetry["counters"] as? [String: Int])?["entity.deliveries"] == 1)
        #expect((telemetry["records"] as? [Any])?.count == 1)
        #expect((telemetry["environment"] as? [String: String])?["os"]?.isEmpty == false)
        #expect((object["metricKit"] as? [Any])?.count == 1)
    }

    @Test func theEnvironmentNamesTheBuildAndTheDevice() {
        let values = PerformanceReport.environment()
        #expect(Set(values.keys).isSuperset(of: ["app", "os", "thermalState", "lowPower", "device"]))
        #expect(values["lowPower"] == "true" || values["lowPower"] == "false")
        #expect(values["device"]?.isEmpty == false)
    }

    // MARK: MetricKit

    @Test func payloadsAreKeptNewestFirstAndTheHitchRatioIsFound() throws {
        let (collector, _, folder) = isolated()
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(collector.payloads().isEmpty && collector.latestScrollHitchRatio() == nil)
        let earlier = Date(timeIntervalSince1970: 1_000_000), later = Date(timeIntervalSince1970: 2_000_000)
        collector.store(Data(#"{"scrollHitchTimeRatio":{"value":9.5,"unit":"ms/s"}}"#.utf8), kind: "metrics", date: earlier)
        collector.store(Data(#"{"nested":[{"scrollHitchTimeRatio":4}]}"#.utf8), kind: "metrics", date: later)
        collector.store(Data(#"{"hangs":2}"#.utf8), kind: "diagnostics", date: later)
        collector.store(Data("not json".utf8), kind: "metrics", date: later.addingTimeInterval(10))
        let names = collector.payloads().map(\.lastPathComponent)
        #expect(names.count == 4)
        #expect(names == names.sorted(by: >), "newest first")
        #expect(collector.payloadObjects().count == 3, "a payload that isn't JSON is left out of the export")
        // The newest metrics file that holds a ratio wins: the unreadable one is skipped.
        #expect(collector.latestScrollHitchRatio() == 4)
        #expect(MetricKitCollector.findHitchRatio(in: ["a": [["scrollHitchTimeRatio": "3.2 ms per s"]]]) == 3.2)
        #expect(MetricKitCollector.findHitchRatio(in: ["scrollHitchTimeRatio": ["value": 1.25]]) == 1.25)
        #expect(MetricKitCollector.findHitchRatio(in: ["other": 1]) == nil)
        #expect(MetricKitCollector.findHitchRatio(in: "plain") == nil)
        collector.removeAll()
        #expect(collector.payloads().isEmpty)
        collector.start()
        collector.start()
    }

    // MARK: Frame monitor

    @Test func aScrollRecordsItsFramesAndCountsHitches() {
        let wasEnabled = Telemetry.isEnabled
        defer { Telemetry.isEnabled = wasEnabled }
        Telemetry.isEnabled = true
        let monitor = FrameMonitor()
        let page = "Frame Test \(UUID().uuidString)"
        #expect(!monitor.isMonitoring)
        monitor.beginScroll(page: page)
        monitor.beginScroll(page: page)
        #expect(monitor.isMonitoring)
        let hitchesBefore = Telemetry.log.records.filter { $0.kind == "\(Telemetry.Name.hitch)" && $0.page == page }.count
        for _ in 0..<20 { monitor.record(frameMs: 8.3, budgetMs: 8.33) }
        monitor.record(frameMs: 30, budgetMs: 8.33)
        monitor.endScroll(page: page)
        monitor.endScroll(page: page)
        #expect(!monitor.isMonitoring)
        let stats = Telemetry.log.scroll[page]
        #expect(stats?.frames == 21)
        #expect(stats?.hitches == 1)
        #expect(stats?.worstFrameMs == 30)
        let hitches = Telemetry.log.records.filter { $0.kind == "\(Telemetry.Name.hitch)" && $0.page == page }
        #expect(hitches.count == hitchesBefore + 1)
    }

    @Test func aMonitorThatIsNotRecordingStillTracksTheScroll() {
        let wasEnabled = Telemetry.isEnabled
        defer { Telemetry.isEnabled = wasEnabled }
        Telemetry.isEnabled = false
        let monitor = FrameMonitor()
        let page = "Quiet Test \(UUID().uuidString)"
        monitor.beginScroll(page: page)
        #expect(monitor.isMonitoring)
        monitor.endScroll(page: page)
        #expect(Telemetry.log.scroll[page] == nil, "no frames, nothing to add")
    }

    // MARK: Rows

    @Test(arguments: [PerformanceRow.Tone.neutral, .good, .warning, .bad], [CGFloat(402), 120])
    func aRowDrawsAtEveryToneAndWidth(tone: PerformanceRow.Tone, width: CGFloat) async {
        let row = PerformanceRow(title: "Recipes", value: "12.4 ms/s", detail: "9 hitches in 540 frames · worst 41 ms", tone: tone)
        let hosted = HostedWindow(List { row }.frame(width: width), size: CGSize(width: width, height: 200))
        defer { hosted.close() }
        await hosted.settle(0.3)
        #expect(hosted.snapshot()?.distinctColors ?? 0 > 2)
    }

    // MARK: Screen

    /// Hosts the screen with the global log, pipeline and MetricKit store in the state the test sets up.
    func screen(seeded: Bool, metricKit payload: String? = nil) async -> HostedWindow {
        let wasEnabled = Telemetry.isEnabled
        Telemetry.log.reset()
        if seeded { PerformanceGallery.seed() }
        Telemetry.isEnabled = wasEnabled
        MetricKitCollector.shared.removeAll()
        if let payload { MetricKitCollector.shared.store(Data(payload.utf8), kind: "metrics") }
        let hosted = HostedWindow(NavigationStack { PerformanceScreen() }, size: Self.phone)
        await hosted.settle(0.8)
        return hosted
    }

    @Test func theScreenShowsEverySectionForSeededMeasurements() async throws {
        let hosted = await screen(seeded: true, metricKit: #"{"scrollHitchTimeRatio":"12.5 ms per s"}"#)
        defer {
            hosted.close()
            MetricKitCollector.shared.removeAll()
            Telemetry.log.reset()
        }
        let seeded = try #require(hosted.snapshot())
        #expect(seeded.distinctColors > 3)
        let empty = await screen(seeded: false)
        defer { empty.close() }
        let blank = try #require(empty.snapshot())
        #expect(blank.differs(from: seeded), "measurements change what the screen draws")
    }
}

/// Drives the screen through its accessibility tree: the recording switch, the sections' rows and the buttons.
@MainActor
@Suite(.serialized, .enabled(if: AXWindow.isAvailable, "Needs accessibility permission for the test host"))
struct PerformanceScreenFlowTests {
    @Test func rowsReadTheirTitleValueAndDetailAndTheSwitchRecords() async throws {
        let wasEnabled = Telemetry.isEnabled
        defer { Telemetry.isEnabled = wasEnabled; Telemetry.log.reset(); MetricKitCollector.shared.removeAll() }
        Telemetry.log.reset()
        PerformanceGallery.seed()
        MetricKitCollector.shared.removeAll()
        let driver = AXWindow(NavigationStack { PerformanceScreen() }, size: PerformanceDiagnosticsTests.phone)
        defer { driver.close() }
        let nodes = await driver.wait { $0.contains { $0.identifier == "performance.screen" } }
        #expect(nodes.contains { $0.identifier == "performance.recording" })
        for heading in ["Scrolling", "Page Loading", "Live Updates", "Actions"] {
            #expect(nodes.contains { $0.role == "AXHeading" && $0.spoken == heading }, "\(heading)")
        }
        // A row is one element: its title is the label and "value. detail" is what it reads.
        #expect(nodes.contains { $0.spoken == "Recipes" }, "the seeded page's scroll row")
        #expect(nodes.contains { $0.spoken == "Shown instantly" })
        #expect(nodes.contains { $0.spoken == "Deliveries" })
        // The recording switch turns the log off and on.
        #expect(Telemetry.isEnabled)
        let off = await driver.press("performance.recording") { _ in !Telemetry.isEnabled }
        #expect(off, "the recording switch turned telemetry off")
    }
}
#endif
