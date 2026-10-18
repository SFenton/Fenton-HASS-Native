import FentonActivityModel
import Foundation
import HassCore
import HassTestSupport
@testable import HassUI
import Testing

private let server = HassServer(baseURL: URL(string: "https://ha.example.com")!)
private let configJSON = #"{"available":true,"push_url":"https://relay/api/fenton_push/apns","bundle_id":"com.sfenton.home"}"#
private let now = Date(timeIntervalSince1970: 1_792_249_200)

private func device() -> MobileAppDevice {
    MobileAppDevice(marketingVersion: "1", build: "2", name: "iPhone", model: "iPhone18,1", osVersion: "27.2",
                    deviceID: "v", apnsEnvironment: .sandbox)
}

@MainActor
private func eventually(_ condition: @MainActor () -> Bool) async -> Bool {
    for _ in 0..<1_000 where !condition() { try? await Task.sleep(for: .milliseconds(5)) }
    return condition()
}

private func dishwasher(_ operation: String = "run", progress: String = "62") -> [EntityState] {
    [
        EntityState(entityId: "sensor.dishwasher_operation_state", state: operation, lastChanged: now.addingTimeInterval(-3_600)),
        EntityState(entityId: "sensor.dishwasher_program_finish_time", state: ISO8601DateFormatter().string(from: now.addingTimeInterval(2_400))),
        EntityState(entityId: "sensor.dishwasher_program_progress", state: progress),
        EntityState(entityId: "select.dishwasher_active_program", state: "dishcare_dishwasher_program_eco_50"),
        EntityState(entityId: "binary_sensor.dishwasher_remote_control", state: "on"),
    ]
}

private func json(_ request: URLRequest) -> [String: Any] {
    (request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
}

/// The Home Live Activity for a session: tokens for Home Assistant, the foreground start, sign-out.
@MainActor
struct LiveActivityCoordinatorTests {
    private func make(enabled: Bool = true, transport: StubHTTPTransport = StubHTTPTransport([]))
        -> (LiveActivityCoordinator, FakeLiveActivityClient, MobileAppCoordinator, EntityStore) {
        let client = FakeLiveActivityClient()
        let mobileApp = MobileAppCoordinator(device: device, store: InMemoryMobileAppRegistrationStore(), transport: transport)
        let coordinator = LiveActivityCoordinator(client: client, mobileApp: mobileApp, isEnabled: enabled, now: { now })
        return (coordinator, client, mobileApp, EntityStore())
    }

    @Test func aRunningDishwasherStartsUpdatesAndEndsTheActivityWhileTheAppIsOpen() async {
        let (coordinator, client, _, entities) = make()
        coordinator.sessionStarted(store: entities)
        entities.replaceAll(dishwasher(), freshness: .live)
        #expect(await eventually { client.activities.count == 1 })
        #expect(client.activities[0].state.jobs.first?.id == "dishwasher")

        entities.apply([EntityState(entityId: "sensor.dishwasher_program_progress", state: "75")])
        #expect(await eventually { client.activities[0].state.jobs.first?.status == "Eco 50° · 75%" })

        entities.apply([EntityState(entityId: "sensor.dishwasher_operation_state", state: "finished")])
        #expect(await eventually { client.activities[0].lifecycle == .ended })
        await coordinator.sessionEnded()
    }

    @Test func theDiskSnapshotOfAColdLaunchStartsNothing() async {
        let (coordinator, client, _, entities) = make()
        coordinator.sessionStarted(store: entities)
        entities.replaceAll(dishwasher(), freshness: .snapshot(savedAt: now.addingTimeInterval(-9_000)))
        for _ in 0..<50 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(client.activities.isEmpty, "a dishwasher that finished hours ago must not start an activity")
        entities.replaceAll(dishwasher(), freshness: .live)
        #expect(await eventually { client.activities.count == 1 })
        await coordinator.sessionEnded()
    }

    @Test func signingOutEndsTheActivityAndStopsFollowing() async {
        let (coordinator, client, _, entities) = make()
        coordinator.sessionStarted(store: entities)
        entities.replaceAll(dishwasher(), freshness: .live)
        #expect(await eventually { client.activities.count == 1 })
        await coordinator.sessionEnded()
        #expect(client.activities[0].lifecycle == .dismissed)
        entities.apply([EntityState(entityId: "sensor.dishwasher_program_progress", state: "90")])
        try? await Task.sleep(for: .milliseconds(50))
        #expect(client.activities.count == 1, "nothing follows the entities after sign-out")
    }

    @Test func aDisabledCoordinatorDoesNothing() async {
        let (coordinator, client, _, entities) = make(enabled: false)
        coordinator.sessionStarted(store: entities)
        entities.replaceAll(dishwasher(), freshness: .live)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(client.activities.isEmpty && !client.isWatching)
        let inert = LiveActivityCoordinator.inert(mobileApp: MobileAppCoordinator(device: device, store: InMemoryMobileAppRegistrationStore()))
        #expect(!inert.isEnabled)
        await coordinator.sessionEnded()
    }

    @Test func thePushToStartTokenReachesHomeAssistantWithTheRegistration() async throws {
        let transport = StubHTTPTransport([(200, configJSON), (201, #"{"webhook_id":"w1"}"#), (200, configJSON), (200, "{}")])
        let (coordinator, client, mobileApp, entities) = make(transport: transport)
        mobileApp.sessionStarted(server: server) { "token" }
        #expect(mobileApp.begin(userID: "u1", userName: nil))
        #expect(mobileApp.setPushToken("ab"))
        await mobileApp.sync()
        coordinator.sessionStarted(store: entities)
        #expect(await eventually { client.isWatching })
        client.emitStartToken("cd01")
        #expect(await eventually { transport.requests.count == 4 })
        let appData = try #require((json(transport.requests[3])["data"] as? [String: Any])?["app_data"] as? [String: Any])
        #expect(appData["start_live_activity_token"] as? String == "cd01")
        #expect(appData["push_token"] as? String == "ab")
        await coordinator.sessionEnded()
    }

    @Test func buttonsReachTheRegistrationWebhook() async throws {
        let registration = MobileAppRegistration(server: server, userID: "u1", webhookID: "w1")
        let transport = StubHTTPTransport([(200, "{}"), (200, "{}")])
        let client = FakeLiveActivityClient()
        let mobileApp = MobileAppCoordinator(device: device, store: InMemoryMobileAppRegistrationStore([registration], active: registration),
                                             transport: transport)
        let coordinator = LiveActivityCoordinator(client: client, mobileApp: mobileApp, now: { now })
        client.startFromPush(state: HomeActivityState(focus: "dishwasher", jobs: [
            ActivityJob(id: "dishwasher", kind: "dishwasher", title: "Dishwasher", status: "", controls: [ActivityControl(id: "stop", title: "Stop")]),
        ]))
        let handled = await coordinator.intentHandler.handle(.control(tag: "fenton-home", job: "dishwasher", control: "stop"))
        #expect(handled)
        let sent = try #require(transport.requests.first)
        #expect(sent.url?.path == "/api/webhook/w1")
        let event = try #require((json(sent)["data"] as? [String: Any]))
        #expect(event["event_type"] as? String == "fenton_live_activity_action")
    }
}

@MainActor
struct LiveActivityRegistrationTests {
    @Test func theWebhookProviderFollowsTheSignedInRegistration() {
        let registration = MobileAppRegistration(server: server, userID: "u1", webhookID: "w1")
        let store = InMemoryMobileAppRegistrationStore([registration], active: registration)
        let mobileApp = MobileAppCoordinator(device: device, store: store, transport: StubHTTPTransport([]))
        let provider = mobileApp.activityWebhookProvider()
        #expect(provider() != nil)
        store.setActive(nil)
        #expect(provider() == nil, "signed out: no webhook")
        let simulator = MobileAppCoordinator(device: device, store: InMemoryMobileAppRegistrationStore([registration], active: registration),
                                             transport: StubHTTPTransport([]), allowsRegistration: false)
        #expect(simulator.activityWebhookProvider()() == nil, "a simulator never reaches the real Home Assistant")
        let disabled = MobileAppCoordinator(device: device, store: InMemoryMobileAppRegistrationStore([registration], active: registration),
                                            transport: StubHTTPTransport([]), isEnabled: false)
        #expect(disabled.activityWebhookProvider()() == nil)
    }

    @Test func aChangedStartTokenSyncsOnceAndOffClearsIt() async throws {
        let transport = StubHTTPTransport([(200, configJSON), (201, #"{"webhook_id":"w1"}"#), (200, configJSON), (200, "{}"), (200, configJSON), (200, "{}")])
        let mobileApp = MobileAppCoordinator(device: device, store: InMemoryMobileAppRegistrationStore(), transport: transport)
        mobileApp.sessionStarted(server: server) { "token" }
        #expect(mobileApp.begin(userID: "u1", userName: nil))
        #expect(mobileApp.setPushToken("ab"))
        await mobileApp.sync()
        #expect(transport.requests.count == 2)
        await mobileApp.registerStartActivityToken("ee")
        await mobileApp.registerStartActivityToken("ee")
        #expect(transport.requests.count == 4, "the same token is not sent twice")
        await mobileApp.registerStartActivityToken(nil)
        #expect(transport.requests.count == 6)
        let appData = try #require((json(transport.requests[5])["data"] as? [String: Any])?["app_data"] as? [String: Any])
        #expect(appData["start_live_activity_token"] == nil)
    }

    @Test func launchPolicy() {
        #expect(LiveActivityLaunchPolicy.isEnabled(environment: [:]))
        #if DEBUG
        for journey in ["FENTON_HASS_TOKEN", "FENTON_UITEST_RESET", "FENTON_GALLERY"] {
            #expect(!LiveActivityLaunchPolicy.isEnabled(environment: [journey: "x"]))
            #expect(LiveActivityLaunchPolicy.isEnabled(environment: [journey: "x", "FENTON_LIVE_ACTIVITY": "1"]))
        }
        #endif
    }
}

@MainActor
struct LiveActivityLinkTests {
    @Test func aTapOnTheActivityOpensTheFocusedJobsPage() throws {
        let push = PushCoordinator.inert()
        let state = HomeActivityFixtures.state(.dishwasher, now: now)
        let url = try #require(ActivityDeepLink.url(for: state))
        #expect(push.openLiveActivity(url))
        #expect(push.pendingRequest?.destination == PushDestination(dashboardPath: "kitchen"))
        #expect(!push.openLiveActivity(URL(string: "https://example.com")!), "any other URL is not ours")
        #expect(!push.openLiveActivity(URL(string: "fentonhome://other")!))
    }
}
