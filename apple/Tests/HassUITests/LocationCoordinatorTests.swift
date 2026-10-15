import Foundation
import HassCore
import HassTestSupport
@testable import HassUI
import Testing

private let server = HassServer(baseURL: URL(string: "https://ha.example.com")!)
private let configJSON = #"{"available":true,"push_url":"https://relay/api/fenton_push/apns","bundle_id":"com.sfenton.home"}"#
private let zonesJSON = """
[{"entity_id":"zone.home","attributes":{"latitude":47.6,"longitude":-122.3,"radius":40,"friendly_name":"Home"}}]
"""
private let fix = LocationFix(latitude: 47.6, longitude: -122.3, horizontalAccuracy: 8, timestamp: Date(timeIntervalSince1970: 2_000_000))

private func device() -> MobileAppDevice {
    MobileAppDevice(marketingVersion: "1", build: "2", name: "iPhone", model: "iPhone18,1", osVersion: "27.2",
                    deviceID: "v", apnsEnvironment: .sandbox)
}

private func freshDefaults() -> UserDefaults {
    UserDefaults(suiteName: "location-tests-\(UUID().uuidString)")!
}

/// Runs the main actor until `condition` holds (the coordinators hand work to unstructured tasks).
@MainActor
private func eventually(_ condition: @MainActor () -> Bool) async {
    for _ in 0..<500 where !condition() {
        try? await Task.sleep(for: .milliseconds(2))
    }
}

private func paths(_ transport: StubHTTPTransport) -> [String] {
    transport.requests.map { request in
        let type = (request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any])?["type"] as? String
        return [request.url?.path ?? "", type].compactMap { $0 }.joined(separator: " ")
    }
}

// MARK: - Location

/// Shadow-mode location: starts on a webhook and permission, only when armed; offers the screen once.
@MainActor
struct LocationCoordinatorTests {
    struct Harness {
        let platform: FakeLocationPlatform
        let transport: StubHTTPTransport
        let store: InMemoryMobileAppRegistrationStore
        let mobileApp: MobileAppCoordinator
        let location: LocationCoordinator
        let defaults: UserDefaults
    }

    func harness(_ permission: LocationPermission, armed: Bool = true, replies: [StubHTTPTransport.Reply] = [],
                 saved: MobileAppRegistration? = nil, defaults: UserDefaults = freshDefaults()) -> Harness {
        let platform = FakeLocationPlatform(permission)
        let transport = StubHTTPTransport(replies)
        let store = InMemoryMobileAppRegistrationStore(saved.map { [$0] } ?? [], active: saved)
        let mobileApp = MobileAppCoordinator(device: device, store: store, transport: transport)
        let location = LocationCoordinator(platform: platform, mobileApp: mobileApp, isReportingArmed: armed,
                                           transport: transport, batteryLevel: { 64 }, defaults: defaults)
        return Harness(platform: platform, transport: transport, store: store, mobileApp: mobileApp, location: location,
                       defaults: defaults)
    }

    @Test func startsOnceRegisteredAndStopsOnSignOut() async {
        let h = harness(LocationPermission(authorization: .always),
                        replies: [(200, configJSON), (201, #"{"webhook_id":"w1"}"#), (200, zonesJSON), (200, "{}"), (200, "{}")])
        h.platform.fixes = [fix]
        h.mobileApp.sessionStarted(server: server) { "token" }
        _ = h.mobileApp.begin(userID: "u1", userName: nil)
        await h.mobileApp.sync()
        await eventually { h.location.reporter.lastReportDate != nil }
        #expect(h.location.reporter.isRunning)
        #expect(paths(h.transport) == ["/api/fenton_push/config", "/api/mobile_app/registrations",
                                       "/api/webhook/w1 get_zones", "/api/webhook/w1 update_location"])

        await h.mobileApp.sessionEnded()
        await eventually { !h.location.reporter.isRunning }
        #expect(!h.location.reporter.isRunning)
    }

    @Test func notArmedNeverReports() async {
        let saved = MobileAppRegistration(server: server, userID: "u1", webhookID: "w1")
        let h = harness(LocationPermission(authorization: .always), armed: false, saved: saved)
        await h.location.resume()
        await h.location.didBecomeActive()
        #expect(!h.location.reporter.isRunning)
        #expect(h.transport.requests.isEmpty)
        #expect(!h.location.isReportingArmed)
    }

    @Test func theToggleArmsAndDisarmsAndPersists() async {
        let saved = MobileAppRegistration(server: server, userID: "u1", webhookID: "w1")
        let h = harness(LocationPermission(authorization: .always), armed: false,
                        replies: [(200, zonesJSON), (200, "{}")], saved: saved)
        h.platform.fixes = [fix]
        await h.location.resume()
        #expect(!h.location.reporter.isRunning)

        await h.location.setReportingArmed(true).value
        #expect(h.location.isReportingArmed)
        #expect(LocationLaunchPolicy.isReportingArmed(environment: [:], defaults: h.defaults), "saved for the next launch")
        #expect(h.location.reporter.isRunning)
        #expect(paths(h.transport) == ["/api/webhook/w1 get_zones", "/api/webhook/w1 update_location"])

        await h.location.setReportingArmed(true).value
        #expect(paths(h.transport).count == 2, "arming again does nothing")

        await h.location.setReportingArmed(false).value
        #expect(!h.location.isReportingArmed)
        #expect(!h.location.reporter.isRunning)
        #expect(!LocationLaunchPolicy.isReportingArmed(environment: [:], defaults: h.defaults))
    }

    @Test func resumesOnTheSavedWebhookWithoutASync() async {
        let saved = MobileAppRegistration(server: server, userID: "u1", webhookID: "w1")
        let h = harness(LocationPermission(authorization: .whenInUse), replies: [(200, zonesJSON), (200, "{}"), (200, "{}")],
                        saved: saved)
        h.platform.fixes = [fix, LocationFix(latitude: 47.7, longitude: -122.3, horizontalAccuracy: 8, timestamp: .now)]
        await h.location.resume()
        #expect(h.location.reporter.isRunning)
        #expect(paths(h.transport) == ["/api/webhook/w1 get_zones", "/api/webhook/w1 update_location"])

        // Coming back to the foreground sends another fix (While Using reports only then).
        await h.location.didBecomeActive()
        #expect(paths(h.transport).last == "/api/webhook/w1 update_location")
        #expect(h.location.reporter.lastTrigger == .launch)
    }

    @Test func startsWhenPermissionArrives() async {
        let saved = MobileAppRegistration(server: server, userID: "u1", webhookID: "w1")
        let h = harness(.notDetermined, replies: [(200, zonesJSON), (200, "{}")], saved: saved)
        h.platform.fixes = [fix]
        await h.location.resume()
        #expect(!h.location.reporter.isRunning, "nothing allowed yet")
        await h.location.didBecomeActive()
        #expect(!h.location.reporter.isRunning)

        let allowed = LocationPermission(authorization: .whenInUse)
        h.platform.permission = allowed
        h.platform.onEvent?(.permissionChanged(allowed))
        await eventually { h.location.reporter.lastReportDate != nil }
        #expect(h.location.reporter.isRunning)
    }

    @Test func aDeletedRegistrationRegistersAgainAndResumes() async {
        let saved = MobileAppRegistration(server: server, userID: "u1", webhookID: "old")
        let h = harness(LocationPermission(authorization: .whenInUse),
                        replies: [(410, ""), (200, configJSON), (410, ""), (201, #"{"webhook_id":"fresh"}"#),
                                  (200, zonesJSON), (200, "{}")],
                        saved: saved)
        h.platform.fixes = [fix]
        h.mobileApp.sessionStarted(server: server) { "token" }
        _ = h.mobileApp.begin(userID: "u1", userName: nil)
        await h.location.resume()
        await eventually { h.location.reporter.lastReportDate != nil }
        #expect(h.store.active?.webhookID == "fresh")
        #expect(h.location.reporter.isRunning)
        #expect(paths(h.transport) == ["/api/webhook/old get_zones", "/api/fenton_push/config", "/api/webhook/old update_registration",
                                       "/api/mobile_app/registrations", "/api/webhook/fresh get_zones",
                                       "/api/webhook/fresh update_location"])
    }

    @Test func offersThePermissionScreenOncePerInstall() {
        let defaults = freshDefaults()
        let first = harness(.notDetermined, defaults: defaults)
        first.location.offerPermissionIfNeeded()
        #expect(first.location.isPresentingPermission)
        first.location.isPresentingPermission = false
        first.location.offerPermissionIfNeeded()
        #expect(!first.location.isPresentingPermission, "once")
        let relaunched = harness(.notDetermined, defaults: defaults)
        relaunched.location.offerPermissionIfNeeded()
        #expect(!relaunched.location.isPresentingPermission, "once per install")

        LocationCoordinator.resetOffers(in: defaults)
        let reset = harness(.notDetermined, defaults: defaults)
        reset.location.offerPermissionIfNeeded()
        #expect(reset.location.isPresentingPermission)

        // Nothing to ask: Always, Off, Approximate.
        for permission in [LocationPermission(authorization: .always), LocationPermission(authorization: .denied),
                           LocationPermission(authorization: .always, isPrecise: false)] {
            let settled = harness(permission)
            settled.location.offerPermissionIfNeeded()
            #expect(!settled.location.isPresentingPermission)
        }
    }

    @Test func remembersTheAlwaysRequest() {
        let defaults = freshDefaults()
        let h = harness(LocationPermission(authorization: .whenInUse), defaults: defaults)
        h.location.offerPermissionIfNeeded()
        #expect(h.location.isPresentingPermission, "While Using can still be upgraded")
        h.location.requestPermission()
        #expect(h.location.hasAskedForAlways)
        #expect(h.platform.calls == ["always"])

        // iOS shows the Always alert once: a later launch neither offers it nor asks again.
        LocationCoordinator.resetOffers(in: freshDefaults())
        defaults.removeObject(forKey: LocationCoordinator.offeredKey)
        let later = harness(LocationPermission(authorization: .whenInUse), defaults: defaults)
        #expect(later.location.hasAskedForAlways)
        later.location.offerPermissionIfNeeded()
        #expect(!later.location.isPresentingPermission)

        let fresh = harness(.notDetermined)
        fresh.location.requestPermission()
        #expect(!fresh.location.hasAskedForAlways)
        #expect(fresh.platform.calls == ["whenInUse"])
    }
}
