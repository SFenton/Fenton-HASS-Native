import Foundation
@testable import HassCore
import HassTestSupport
import Testing

let zonesJSON = """
[{"entity_id":"zone.home","attributes":{"latitude":47.6,"longitude":-122.3,"radius":40,"friendly_name":"Home"}},
 {"entity_id":"zone.work","attributes":{"latitude":47.645,"longitude":-122.3,"radius":150,"friendly_name":"Work"}}]
"""

@MainActor
@Suite("Location reporter")
struct LocationReporterTests {
    let clock = Date(timeIntervalSince1970: 2_000_000)

    func reporter(_ platform: FakeLocationPlatform, _ transport: StubHTTPTransport, presence: Bool = true) -> LocationReporter {
        LocationReporter(
            platform: platform,
            client: MobileAppWebhookClient(source: FixedMobileAppWebhookSource(mobileAppWebhook), transport: transport),
            isPresenceDevice: presence, batteryLevel: { 64 }, now: { [clock] in clock }
        )
    }

    /// The `data` of the `update_location` command at `index` among the recorded requests.
    func locationData(_ transport: StubHTTPTransport, _ index: Int) throws -> [String: Any] {
        let body = try sentBody(transport.requests[index])
        #expect(body["type"] as? String == "update_location")
        return try #require(body["data"] as? [String: Any])
    }

    @Test func permissionIsRequestedInTwoSteps() {
        let platform = FakeLocationPlatform(.notDetermined)
        let subject = reporter(platform, StubHTTPTransport([]))
        subject.requestPermission()
        platform.permission = LocationPermission(authorization: .whenInUse)
        let upgraded = reporter(platform, StubHTTPTransport([]))
        upgraded.requestPermission()
        for authorization in [LocationPermission.Authorization.always, .denied, .restricted] {
            platform.permission = LocationPermission(authorization: authorization)
            reporter(platform, StubHTTPTransport([])).requestPermission()
        }
        #expect(platform.calls == ["whenInUse", "always"])
    }

    @Test func startWithAlwaysMonitorsZonesAndSendsALaunchFix() async throws {
        let platform = FakeLocationPlatform(LocationPermission(authorization: .always))
        platform.fixes = [fixNorth(of: 0, accuracy: 8)]
        let transport = StubHTTPTransport([(200, zonesJSON), (200, "{}")])
        let subject = reporter(platform, transport)
        await subject.start()
        #expect(subject.isRunning)
        #expect(platform.calls == ["startSignificant", "monitor 2"])
        #expect(subject.monitoredRegions.map(\.id) == ["zone.home", "zone.work"])
        #expect(subject.monitoredRegions[0].radius == 100)
        let data = try locationData(transport, 1)
        #expect(data["battery"] as? Int == 64)
        #expect(data["location_name"] == nil)
        #expect(subject.lastTrigger == .launch)
        #expect(subject.lastReportDate == clock)
        #expect(subject.lastError == nil)

        await subject.start()
        #expect(transport.requests.count == 2, "Starting twice does nothing")
    }

    @Test func whileUsingOnlySendsFixesWithoutBackgroundMonitoring() async throws {
        let platform = FakeLocationPlatform(LocationPermission(authorization: .whenInUse))
        platform.fixes = [fixNorth(of: 0)]
        let transport = StubHTTPTransport([(200, zonesJSON), (200, "{}")])
        let subject = reporter(platform, transport)
        await subject.start()
        #expect(platform.calls.isEmpty)
        #expect(subject.monitoredRegions.isEmpty)
        #expect(transport.requests.count == 2)
    }

    @Test func iPadsAndUnauthorizedDevicesNeverStart() async {
        let transport = StubHTTPTransport([])
        let iPad = reporter(FakeLocationPlatform(LocationPermission(authorization: .always)), transport, presence: false)
        await iPad.start()
        let denied = reporter(FakeLocationPlatform(LocationPermission(authorization: .denied)), transport)
        await denied.start()
        #expect(!iPad.isRunning && !denied.isRunning)
        #expect(transport.requests.isEmpty)
        #expect(await denied.report(.manual) == false)
        #expect(!LocationReporter.isPresenceDevice(isPad: true))
        #expect(LocationReporter.isPresenceDevice(isPad: false))
        #expect(!LocationReporter.deviceIsPresenceDevice, "The macOS test host is not a phone")
    }

    @Test func zoneEntryAndExitSendTheZoneResult() async throws {
        let platform = FakeLocationPlatform(LocationPermission(authorization: .always))
        platform.fixes = [fixNorth(of: 5000), fixNorth(of: 10, accuracy: 15), fixNorth(of: 2000, accuracy: 30)]
        let transport = StubHTTPTransport([(200, zonesJSON), (200, "{}"), (200, "{}"), (200, "{}")])
        let subject = reporter(platform, transport)
        await subject.start()

        await subject.handle(.zone(.entered("zone.home")))
        let entered = try locationData(transport, 2)
        #expect(entered["location_name"] as? String == "home")
        #expect(subject.lastTrigger == .regionEntered)

        await subject.handle(.zone(.exited("zone.home")))
        #expect(try locationData(transport, 3)["location_name"] as? String == "not_home")
        #expect(subject.lastTrigger == .regionExited)
    }

    @Test func zoneEntryWithoutAFixReportsTheZoneCenter() async throws {
        let platform = FakeLocationPlatform(LocationPermission(authorization: .always))
        platform.fixes = [fixNorth(of: 3000)]
        let transport = StubHTTPTransport([(200, zonesJSON), (200, "{}"), (200, "{}")])
        let subject = reporter(platform, transport)
        await subject.start()
        await subject.handle(.zone(.entered("zone.work")))
        let data = try locationData(transport, 2)
        #expect(data["gps"] as? [Double] == [47.645, -122.3])
        #expect(data["gps_accuracy"] as? Int == 150)
        #expect(data["location_name"] as? String == "Work")

        // An exit, or an unknown zone, without a fix sends nothing.
        await subject.handle(.zone(.exited("zone.work")))
        await subject.handle(.zone(.entered("zone.unknown")))
        #expect(transport.requests.count == 3)
    }

    @Test func significantChangesAreFilteredAndReplanZones() async throws {
        let platform = FakeLocationPlatform(LocationPermission(authorization: .always))
        platform.fixes = [fixNorth(of: 0)]
        let transport = StubHTTPTransport([(200, zonesJSON), (200, "{}"), (200, "{}")])
        let subject = reporter(platform, transport)
        await subject.start()
        await subject.handle(.significantChange(fixNorth(of: 3, at: 5)))
        #expect(transport.requests.count == 2, "A duplicate is not sent")
        await subject.handle(.significantChange(fixNorth(of: 900, accuracy: 300, at: 60)))
        #expect(transport.requests.count == 2, "An inaccurate fix is not sent")
        await subject.handle(.significantChange(fixNorth(of: 4000, at: 120)))
        #expect(transport.requests.count == 3)
        #expect(subject.lastTrigger == .significantLocationChange)
        #expect(subject.monitoredRegions.map(\.id) == ["zone.home", "zone.work"])
    }

    @Test func eventsWhileStoppedAreIgnored() async {
        let platform = FakeLocationPlatform(LocationPermission(authorization: .always))
        let transport = StubHTTPTransport([])
        let subject = reporter(platform, transport)
        await subject.handle(.significantChange(fixNorth(of: 0)))
        await subject.handle(.zone(.entered("zone.home")))
        await subject.refreshZones()
        await subject.stop()
        await subject.handle(.permissionChanged(LocationPermission(authorization: .denied)))
        #expect(subject.permission.authorization == .denied)
        #expect(transport.requests.isEmpty)
        #expect(platform.calls.isEmpty)
    }

    @Test func permissionChangesFollowThePlatform() async {
        let platform = FakeLocationPlatform(LocationPermission(authorization: .whenInUse))
        platform.fixes = [fixNorth(of: 0)]
        let transport = StubHTTPTransport([(200, zonesJSON), (200, "{}")])
        let subject = reporter(platform, transport)
        await subject.start()

        await subject.handle(.permissionChanged(LocationPermission(authorization: .always)))
        #expect(platform.calls == ["startSignificant", "monitor 2"])

        await subject.handle(.permissionChanged(LocationPermission(authorization: .always)))
        #expect(platform.calls.count == 2, "No change, nothing to do")

        await subject.handle(.permissionChanged(LocationPermission(authorization: .always, isPrecise: false)))
        #expect(platform.calls == ["startSignificant", "monitor 2", "stopSignificant", "stopMonitoring"])
        #expect(subject.monitoredRegions.isEmpty)

        await subject.handle(.permissionChanged(LocationPermission(authorization: .denied)))
        #expect(!subject.isRunning)
        #expect(platform.calls.suffix(2) == ["stopSignificant", "stopMonitoring"])
    }

    @Test func aGoneRegistrationStopsReporting() async {
        let platform = FakeLocationPlatform(LocationPermission(authorization: .always))
        platform.fixes = [fixNorth(of: 0)]
        let transport = StubHTTPTransport([(200, zonesJSON), (410, "")])
        let subject = reporter(platform, transport)
        await subject.start()
        #expect(subject.lastError == .registrationGone)
        #expect(!subject.isRunning)
        #expect(subject.lastTrigger == nil)
    }

    @Test func zoneFailuresAreRecordedAndAFailedSendCanBeRetried() async throws {
        let platform = FakeLocationPlatform(LocationPermission(authorization: .always))
        platform.fixes = [fixNorth(of: 0), fixNorth(of: 0)]
        let transport = StubHTTPTransport([(500, ""), (503, ""), (200, "{}")])
        let subject = reporter(platform, transport)
        await subject.start()
        #expect(subject.isRunning, "A server error keeps reporting on")
        #expect(subject.lastError == .status(503))
        #expect(subject.monitoredRegions.isEmpty)
        #expect(await subject.report(.manual))
        #expect(subject.lastError == nil)
        #expect(await subject.report(.manual) == false, "No fix")
    }

    @Test func cancellationIsNotAnError() async {
        let platform = FakeLocationPlatform(LocationPermission(authorization: .always))
        let transport = StubHTTPTransport([])
        transport.error = CancellationError()
        let subject = reporter(platform, transport)
        await subject.start()
        #expect(subject.lastError == nil)
        #expect(subject.isRunning)
    }

    @Test func platformEventsReachTheReporter() async {
        let platform = FakeLocationPlatform(.notDetermined)
        let subject = reporter(platform, StubHTTPTransport([]))
        platform.onEvent?(.permissionChanged(LocationPermission(authorization: .whenInUse)))
        for _ in 0..<50 where subject.permission.authorization != .whenInUse { await Task.yield() }
        #expect(subject.permission.authorization == .whenInUse)
    }

    @Test func unregisteredStopsToo() async {
        let platform = FakeLocationPlatform(LocationPermission(authorization: .always))
        let subject = LocationReporter(
            platform: platform, client: MobileAppWebhookClient(source: FixedMobileAppWebhookSource(nil), transport: StubHTTPTransport([])),
            isPresenceDevice: true
        )
        await subject.start()
        #expect(subject.lastError == .notRegistered)
        #expect(!subject.isRunning)
    }
}
