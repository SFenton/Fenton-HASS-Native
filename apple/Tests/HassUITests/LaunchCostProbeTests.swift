#if os(macOS)
import Foundation
import HassTelemetry
@testable import HassUI
import SwiftUI
import Testing

extension LoginTests {
/// The launch cost probe: one line per phase, with the meter's numbers and the signpost intervals.
@MainActor
@Suite(.serialized)
struct LaunchCostProbeTests {
    @Test func aPhaseWritesOneLineWithTheMetersNumbersAndTheIntervals() async throws {
        let was = LaunchCostProbe.isEnabled
        LaunchCostProbe.isEnabled = true
        defer { LaunchCostProbe.isEnabled = was }
        let file = FileManager.default.temporaryDirectory.appending(path: "launchcost-\(UUID()).tsv")
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(LaunchCostProbe.finish() == nil, "nothing is running")

        LaunchCostProbe.begin("arrival")
        LaunchCostProbe.begin("ignored") // a phase is running: the second begin does nothing
        try await Task.sleep(for: .milliseconds(50))
        let line = try #require(LaunchCostProbe.finish(environment: ["FENTON_LAUNCHCOST_FILE": file.path]))
        #expect(line.contains("p95_ms=") && line.contains("over16="))
        #expect(LaunchCostProbe.latest == line)
        let written = try String(contentsOf: file, encoding: .utf8)
        #expect(written.hasPrefix("LAUNCHCOST\tarrival\t") && written.contains("LAUNCHCOST_DONE\tarrival"))
        #expect(!written.contains("ignored"))

        // A second run appends rather than replaces.
        LaunchCostProbe.begin("snapshot")
        LaunchCostProbe.finish(environment: ["FENTON_LAUNCHCOST_FILE": file.path])
        #expect(try String(contentsOf: file, encoding: .utf8).components(separatedBy: "LAUNCHCOST_DONE").count == 3)
    }

    @Test func aWindowMeasuresForTwoSecondsAndEndsItself() async {
        let was = LaunchCostProbe.isEnabled
        LaunchCostProbe.isEnabled = true
        defer { LaunchCostProbe.isEnabled = was }
        await LaunchCostProbe.measureWindow("intro")
        #expect(LaunchCostProbe.latest.contains("seconds="))
        #expect(LaunchCostProbe.finish() == nil, "the window closed its own run")
    }

    @Test func aLaunchThatDoesNotMeasureDoesNothing() async {
        let was = LaunchCostProbe.isEnabled
        LaunchCostProbe.isEnabled = false
        defer { LaunchCostProbe.isEnabled = was }
        LaunchCostProbe.begin("intro")
        #expect(LaunchCostProbe.finish() == nil)
        await LaunchCostProbe.measureWindow("intro")
    }

    @Test func theLineCarriesTheLatestOfEachIntervalThatWasRecorded() {
        let meter = MainThreadCostMeter()
        meter.begin()
        let report = meter.finish()
        let records = [
            TelemetryRecord(kind: "Arrival", durationMs: 900), TelemetryRecord(kind: "Arrival", durationMs: 850),
            TelemetryRecord(kind: "SignIn", durationMs: 420), TelemetryRecord(kind: "ContentReady", durationMs: 5),
        ]
        let line = LaunchCostProbe.line(for: report, records: records)
        #expect(line.contains("Arrival_ms=850.00") && line.contains("SignIn_ms=420.00"))
        #expect(!line.contains("Launch_ms") && !line.contains("ContentReady"))
    }

    @Test func theElementCarriesTheLastLine() {
        #expect(ImageRenderer(content: LaunchCostProbeElement()).cgImage != nil)
    }
}
}
#endif
