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
