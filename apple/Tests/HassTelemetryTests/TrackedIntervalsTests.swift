import Foundation
@testable import HassTelemetry
import Testing

/// Named intervals begun in one place and ended in another, once.
@Suite(.serialized)
struct TrackedIntervalsTests {
    @Test func theNamesAreTheOnesUITestsReadInTheTelemetryCategory() {
        #expect(Telemetry.subsystem == "com.sfenton.home" && Telemetry.category == "Performance")
        #expect(["\(Telemetry.Name.launch)", "\(Telemetry.Name.snapshotShown)", "\(Telemetry.Name.signIn)",
                 "\(Telemetry.Name.arrival)", "\(Telemetry.Name.reconnect)"] == ["Launch", "SnapshotShown", "SignIn", "Arrival", "Reconnect"])
    }

    @Test func anIntervalEndsOnceAndReportsItsLength() async throws {
        let intervals = TrackedIntervals()
        #expect(intervals.end(Telemetry.Name.signIn) == nil, "ending an interval that never began does nothing")
        intervals.begin(Telemetry.Name.signIn)
        #expect(intervals.isOpen(Telemetry.Name.signIn))
        intervals.begin(Telemetry.Name.signIn) // already open: keeps the first start
        try await Task.sleep(for: .milliseconds(20))
        let ms = try #require(intervals.end(Telemetry.Name.signIn))
        #expect(ms >= 15)
        #expect(!intervals.isOpen(Telemetry.Name.signIn))
        #expect(intervals.end(Telemetry.Name.signIn) == nil, "a second end does nothing")
    }

    @Test func aCancelledIntervalClosesWithoutALogEntry() {
        let intervals = TrackedIntervals()
        let was = Telemetry.isEnabled
        Telemetry.isEnabled = true
        defer { Telemetry.isEnabled = was }
        func logged() -> Int { Telemetry.log.records.filter { $0.kind == "Reconnect" }.count }
        let before = logged()
        intervals.cancel(Telemetry.Name.reconnect) // not open: nothing happens
        intervals.begin(Telemetry.Name.reconnect)
        intervals.cancel(Telemetry.Name.reconnect)
        #expect(!intervals.isOpen(Telemetry.Name.reconnect))
        #expect(logged() == before)
    }

    @Test func aFinishedIntervalLandsInTheInAppLogWhenRecording() {
        let intervals = TrackedIntervals()
        let was = Telemetry.isEnabled
        Telemetry.isEnabled = true
        defer { Telemetry.isEnabled = was }
        func logged() -> Int { Telemetry.log.records.filter { $0.kind == "Arrival" && $0.durationMs != nil }.count }
        let before = logged()
        intervals.begin(Telemetry.Name.arrival)
        intervals.end(Telemetry.Name.arrival)
        #expect(logged() == before + 1)
        Telemetry.isEnabled = false
        intervals.begin(Telemetry.Name.arrival)
        intervals.end(Telemetry.Name.arrival)
        #expect(logged() == before + 1, "nothing is logged while recording is off")
    }

    @Test func theSharedFacadeBeginsEndsAndCancels() {
        Telemetry.cancelTracked(Telemetry.Name.launch)
        Telemetry.beginTracked(Telemetry.Name.launch)
        #expect(Telemetry.isTracked(Telemetry.Name.launch))
        #expect(Telemetry.endTracked(Telemetry.Name.launch) != nil)
        Telemetry.beginTracked(Telemetry.Name.launch)
        Telemetry.cancelTracked(Telemetry.Name.launch)
        #expect(!Telemetry.isTracked(Telemetry.Name.launch))
    }
}
