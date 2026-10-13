import Foundation
import HassDesign
import HassTelemetry

/// A snapshot of the telemetry for the screen and the export file.
struct PerformanceReport {
    struct PageScroll: Identifiable {
        var page: String
        var id: String { page }
        var stats: ScrollStats
    }

    struct PageReady: Identifiable {
        var name: String
        var id: String { name }
        var stats: TelemetryStats
    }

    var scroll: [PageScroll]
    var pages: [PageReady]
    var stats: [String: TelemetryStats]
    var counters: [String: Int]
    var recordCount: Int
    var diskBytes: Int
    var diskFiles: Int
    var metricKitPayloads: Int
    var metricKitHitchRatio: Double?

    func counter(_ name: String) -> Int { counters[name] ?? 0 }

    @MainActor
    static func current(log: TelemetryLog = Telemetry.log, pipeline: ImagePipeline = .shared,
                        metricKit: MetricKitCollector = .shared) -> PerformanceReport {
        let stats = log.stats
        let prefix = "\(Telemetry.Name.contentReady)@"
        let disk = pipeline.diskUsage()
        return PerformanceReport(
            scroll: log.scroll.map { PageScroll(page: $0.key, stats: $0.value) }.sorted { $0.stats.hitchRatio > $1.stats.hitchRatio },
            pages: stats.filter { $0.key.hasPrefix(prefix) }
                .map { PageReady(name: String($0.key.dropFirst(prefix.count)), stats: $0.value) }
                .sorted { $0.stats.p50 > $1.stats.p50 },
            stats: stats,
            counters: log.counters,
            recordCount: log.records.count,
            diskBytes: disk.bytes,
            diskFiles: disk.files,
            metricKitPayloads: metricKit.payloads().count,
            metricKitHitchRatio: metricKit.latestScrollHitchRatio()
        )
    }

    /// Build and device facts for the export.
    @MainActor
    static func environment() -> [String: String] {
        let info = Bundle.main.infoDictionary ?? [:]
        var values: [String: String] = [
            "app": "\(info["CFBundleShortVersionString"] ?? "?") (\(info["CFBundleVersion"] ?? "?"))",
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "thermalState": "\(ProcessInfo.processInfo.thermalState.rawValue)",
            "lowPower": "\(ProcessInfo.processInfo.isLowPowerModeEnabled)",
        ]
        #if targetEnvironment(simulator)
        values["device"] = "simulator"
        #else
        var system = utsname()
        uname(&system)
        values["device"] = withUnsafeBytes(of: &system.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        #endif
        return values
    }

    /// Writes the export (telemetry plus MetricKit payloads) to a temporary JSON file.
    @MainActor
    static func writeExport(log: TelemetryLog = Telemetry.log, metricKit: MetricKitCollector = .shared) throws -> URL {
        let telemetry = try JSONSerialization.jsonObject(with: log.exportJSON(environment: environment()))
        let object: [String: Any] = ["telemetry": telemetry, "metricKit": metricKit.payloadObjects()]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("FentonHome-telemetry-\(stamp).json")
        try data.write(to: url, options: .atomic)
        return url
    }
}
