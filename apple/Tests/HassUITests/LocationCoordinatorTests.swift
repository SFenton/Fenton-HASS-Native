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

// MARK: - Shared registration

/// The shared `mobile_app` registration: published to listeners, cleared on sign-out, read by location.
@MainActor
struct MobileAppCoordinatorTests {
    @Test func publishesTheRegistrationAndClearsItOnSignOut() async {
        let store = InMemoryMobileAppRegistrationStore()
        let transport = StubHTTPTransport([(404, ""), (201, #"{"webhook_id":"w1"}"#), (200, "{}")])
        let mobileApp = MobileAppCoordinator(device: device, store: store, transport: transport)
        var seen: [MobileAppRegistration?] = []
        mobileApp.onRegistrationChange { seen.append($0) }
        #expect(!mobileApp.begin(userID: "u1", userName: nil), "no session yet")
        #expect(!mobileApp.savedWebhookExists)

        mobileApp.sessionStarted(server: server) { "token" }
        #expect(mobileApp.begin(userID: "u1", userName: "Stephen Fenton"))
        #expect(!mobileApp.begin(userID: "u1", userName: "Stephen Fenton"), "same user again")
        await mobileApp.sync()
        let registration = MobileAppRegistration(server: server, userID: "u1", webhookID: "w1")
        #expect(mobileApp.registration == registration)
        #expect(mobileApp.savedWebhookExists)
        #expect(await mobileApp.webhookSource.currentWebhook() == registration.webhook)

        await mobileApp.sessionEnded()
        #expect(mobileApp.registration == nil)
        #expect(!mobileApp.savedWebhookExists)
        #expect(seen == [registration, nil])
        await #expect(throws: PushClientError.signedOut) {
            try await mobileApp.fireAction(PushActionEvent(action: "A", tag: nil))
        }
    }

    @Test func disabledNeverRegisters() async {
        let saved = MobileAppRegistration(server: server, userID: "u1", webhookID: "w1")
        let transport = StubHTTPTransport([])
        let mobileApp = MobileAppCoordinator(device: device, store: InMemoryMobileAppRegistrationStore([saved], active: saved),
                                             transport: transport, isEnabled: false)
        mobileApp.sessionStarted(server: server) { "token" }
        #expect(!mobileApp.begin(userID: "u1", userName: nil))
        await mobileApp.sync()
        #expect(!mobileApp.savedWebhookExists, "a journey never reports on a real webhook")
        #expect(transport.requests.isEmpty)
    }

    @Test func aNewTokenSyncsOnce() {
        let mobileApp = MobileAppCoordinator(device: device, store: InMemoryMobileAppRegistrationStore())
        #expect(mobileApp.setPushToken("ab"))
        #expect(!mobileApp.setPushToken("ab"))
        #expect(mobileApp.setPushToken("cd"))
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

// MARK: - Launch policy

struct LocationLaunchPolicyTests {
    @Test func phonesOnlyAndNotInJourneys() {
        #expect(LocationLaunchPolicy.isEnabled(environment: [:], isPresenceDevice: true))
        #expect(!LocationLaunchPolicy.isEnabled(environment: [:], isPresenceDevice: false), "never on iPad")
        #expect(!LocationLaunchPolicy.isEnabled(environment: ["FENTON_LOCATION": "1"], isPresenceDevice: false))
        for key in ["FENTON_HASS_TOKEN", "FENTON_UITEST_RESET", "FENTON_GALLERY"] {
            #expect(!LocationLaunchPolicy.isEnabled(environment: [key: "1"], isPresenceDevice: true))
            #expect(LocationLaunchPolicy.isEnabled(environment: [key: "1", "FENTON_LOCATION": "1"], isPresenceDevice: true))
        }
    }

    @Test func reportingIsArmedPerInstall() {
        let defaults = freshDefaults()
        #expect(!LocationLaunchPolicy.isReportingArmed(environment: [:], defaults: defaults))
        #expect(LocationLaunchPolicy.isReportingArmed(environment: ["FENTON_LOCATION_REPORT": "1"], defaults: defaults))
        #expect(LocationLaunchPolicy.isReportingArmed(environment: [:], defaults: defaults), "persists")
        #expect(!LocationLaunchPolicy.isReportingArmed(environment: ["FENTON_LOCATION_REPORT": "0"], defaults: defaults))
        #expect(!LocationLaunchPolicy.isReportingArmed(environment: [:], defaults: defaults))
    }
}
