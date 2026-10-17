import FentonActivityModel
import Foundation
@testable import HassCore
import Testing

@MainActor
struct LiveActivityTokenReporterTests {
    private let now = LiveActivityFixtures.now

    private final class Registered: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String?] = []
        func add(_ value: String?) { lock.withLock { values.append(value) } }
        var all: [String?] { lock.withLock { values } }
    }

    private func make(enabled: Bool = true, webhook: RecordingActivityWebhook? = RecordingActivityWebhook())
        -> (LiveActivityTokenReporter, FakeLiveActivityClient, RecordingActivityWebhook?, Registered) {
        let client = FakeLiveActivityClient(enabled: enabled)
        let registered = Registered()
        let now = now
        let reporter = LiveActivityTokenReporter(client: client, webhook: { webhook }, registerStartToken: { registered.add($0) },
                                                 now: { now })
        return (reporter, client, webhook, registered)
    }

    private let state = HomeActivityState(jobs: [ActivityJob(id: "dishwasher", kind: "dishwasher", title: "Dishwasher", status: "")])

    @Test func theStartTokenGoesToTheRegistrationAndOffRemovesIt() async {
        let (reporter, client, _, registered) = make()
        reporter.start()
        reporter.start()
        #expect(await eventually { client.isWatching })
        client.emitStartToken("aa01")
        #expect(await eventually { registered.all == ["aa01"] })
        client.setEnabled(false)
        #expect(await eventually { registered.all == ["aa01", nil] })
        client.setEnabled(false)
        client.setEnabled(true)
        #expect(await eventually { registered.all == ["aa01", nil, "aa01"] })
        client.emitStartToken("bb02")
        #expect(await eventually { registered.all.last == "bb02" })
        reporter.stop()
    }

    @Test func aTokenWhileOffIsKeptUntilTheyTurnItOn() async {
        let (reporter, client, _, registered) = make(enabled: false)
        reporter.start()
        #expect(await eventually { client.isWatching })
        client.emitStartToken("cc03")
        client.setEnabled(true)
        #expect(await eventually { registered.all == ["cc03"] })
        reporter.stop()
    }

    @Test func eachActivityReportsItsUpdateTokenForEightHours() async {
        let (reporter, client, webhook, _) = make()
        reporter.start()
        #expect(await eventually { client.isWatching })
        let local = client.startFromPush(state: state)
        // The same activity seen twice is followed once.
        reporter.observe(local)
        #expect(await eventually { client.isWatching(activity: local.id) })
        client.emitPushToken(id: local.id, "dd04")
        let expected = RecordingActivityWebhook.Sent.token(tag: "fenton-home", token: "dd04", expiresAt: now.addingTimeInterval(8 * 3600))
        #expect(await eventually { webhook?.sent == [expected] })
        reporter.stop()
    }

    @Test func anActivityAlreadyRunningAtLaunchIsFollowed() async {
        let (reporter, client, webhook, _) = make()
        let existing = client.startFromPush(state: state)
        reporter.start()
        #expect(await eventually { client.isWatching(activity: existing.id) })
        client.emitPushToken(id: existing.id, "ee05")
        #expect(await eventually { webhook?.sent.count == 1 })
        reporter.stop()
    }

    @Test func aSwipeAwayDropsTheTokenAndTellsHomeAssistant() async {
        let (reporter, client, webhook, _) = make()
        reporter.start()
        #expect(await eventually { client.isWatching })
        let record = client.startFromPush(state: state)
        #expect(await eventually { client.isWatching(activity: record.id) })
        client.emitLifecycle(id: record.id, .dismissed)
        #expect(await eventually { webhook?.sent.count == 2 })
        #expect(webhook?.sent == [.dismissed(tag: "fenton-home"),
                                  .event(LiveActivityEventType.dismissed, ["tag": "fenton-home", "jobs": "dishwasher"])])
        reporter.stop()
    }

    @Test func anEndedActivityOnlyDropsTheToken() async {
        let (reporter, client, webhook, _) = make()
        reporter.start()
        #expect(await eventually { client.isWatching })
        let record = client.startFromPush(state: state)
        #expect(await eventually { client.isWatching(activity: record.id) })
        client.emitLifecycle(id: record.id, .stale)
        client.emitLifecycle(id: record.id, .ended)
        #expect(await eventually { webhook?.sent == [.dismissed(tag: "fenton-home")] })
        reporter.stop()
    }

    @Test func nothingIsSentWithoutARegistration() async {
        let (reporter, client, _, _) = make(webhook: nil)
        reporter.start()
        #expect(await eventually { client.isWatching })
        let record = client.startFromPush(state: state)
        #expect(await eventually { client.isWatching(activity: record.id) })
        client.emitPushToken(id: record.id, "ff06")
        client.emitLifecycle(id: record.id, .dismissed)
        // Nothing to assert on a send that never happens; the watchers finish without one.
        for _ in 0..<100 { await Task.yield() }
        reporter.stop()
    }
}

struct HomeActivityActionHandlerTests {
    private let state = HomeActivityState(focus: "dishwasher", jobs: [
        ActivityJob(id: "dishwasher", kind: "dishwasher", title: "Dishwasher", status: "Eco 50° · 62%",
                    symbol: "dishwasher", tint: "cleaning", controls: [ActivityControl(id: "stop", title: "Stop", role: .destructive)]),
        ActivityJob(id: "fan.master", kind: "bathroom_fan", title: "Master Bath Fan", status: "Off in",
                    symbol: "fan", tint: "air", controls: [ActivityControl(id: "cancel_timer", title: "Cancel Timer")]),
    ])

    private func make(webhook: RecordingActivityWebhook? = RecordingActivityWebhook())
        -> (HomeActivityActionHandler, FakeLiveActivityClient, RecordingActivityWebhook?, LiveActivityRecord) {
        let client = FakeLiveActivityClient()
        let record = client.startFromPush(state: state)
        return (HomeActivityActionHandler(client: client, webhook: { webhook }), client, webhook, record)
    }

    @Test func pagingFocusesLocallyAndTellsHomeAssistant() async {
        let (handler, client, webhook, record) = make()
        #expect(await handler.handle(.focus(tag: "fenton-home", job: "fan.master")))
        let updated = client.activities[0].state
        #expect(updated.focus == "fan.master" && updated.url == "/sfenton-react-dash/home?path=master-bathroom")
        #expect(webhook?.sent == [.event(LiveActivityEventType.focus, ["tag": "fenton-home", "job": "fan.master"])])
        // Focusing what is already focused does nothing.
        let before = client.calls.count
        #expect(await handler.handle(.focus(tag: "fenton-home", job: "fan.master")))
        #expect(client.calls.count == before && record.id == "act-1")
    }

    @Test func aControlShowsStoppingThenFiresTheEvent() async {
        let (handler, client, webhook, _) = make()
        #expect(await handler.handle(.control(tag: "fenton-home", job: "dishwasher", control: "stop")))
        let job = client.activities[0].state.jobs[0]
        #expect(job.phase == .stopping && job.controls.isEmpty)
        #expect(webhook?.sent == [.event(LiveActivityEventType.action, ["tag": "fenton-home", "job": "dishwasher", "control": "stop"])])
    }

    @Test func aFailedControlPutsTheButtonBackWithAReason() async {
        let (handler, client, webhook, _) = make()
        webhook?.fails = true
        #expect(await handler.handle(.control(tag: "fenton-home", job: "dishwasher", control: "stop")) == false)
        let job = client.activities[0].state.jobs[0]
        #expect(job.phase == .running && job.controls.map(\.id) == ["stop"] && job.status == "Couldn't reach Home")
        let noRegistration = make(webhook: nil)
        #expect(await noRegistration.0.handle(.control(tag: "fenton-home", job: "dishwasher", control: "stop")) == false)
    }

    @Test func anUnknownControlJobOrActivityIsRefused() async {
        let (handler, client, webhook, _) = make()
        #expect(await handler.handle(.control(tag: "fenton-home", job: "dishwasher", control: "launch")) == false)
        #expect(await handler.handle(.control(tag: "fenton-home", job: "gone", control: "stop")) == false)
        #expect(await handler.handle(.focus(tag: "other", job: "dishwasher")) == false)
        #expect(client.calls.isEmpty && webhook?.sent.isEmpty == true, "nothing was changed or sent")
    }

    @Test func pagingToAnUnlistedJobChangesNothing() async {
        let (handler, client, webhook, _) = make()
        #expect(await handler.handle(.focus(tag: "fenton-home", job: "gone")))
        #expect(client.calls.isEmpty && webhook?.sent.isEmpty == true)
    }

    @Test func pagingStillWorksWhenHomeAssistantCannotBeReached() async {
        let (handler, client, webhook, _) = make()
        webhook?.fails = true
        #expect(await handler.handle(.focus(tag: "fenton-home", job: "fan.master")))
        #expect(client.activities[0].state.focus == "fan.master")
    }
}

struct LiveActivityWebhookTests {
    private let server = HassServer(baseURL: URL(string: "https://ha.example.com")!)

    private func sender(_ transport: StubHTTPTransport) -> MobileAppLiveActivityWebhook {
        MobileAppLiveActivityWebhook(client: MobileAppWebhookClient(
            source: FixedMobileAppWebhookSource(MobileAppWebhook(server: server, webhookID: "hook1")), transport: transport))
    }

    private func body(_ transport: StubHTTPTransport, _ index: Int = 0) throws -> [String: Any] {
        let data = try #require(transport.requests[index].httpBody)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func tokensDismissalsAndEventsAreMobileAppWebhookCommands() async throws {
        let transport = StubHTTPTransport([(200, "{}"), (200, "{}"), (200, "{}")])
        let sender = sender(transport)
        try await sender.reportToken(tag: "fenton-home", token: "ab12", expiresAt: Date(timeIntervalSince1970: 1_792_278_000))
        try await sender.reportDismissed(tag: "fenton-home")
        try await sender.fireEvent(LiveActivityEventType.action, data: ["tag": "fenton-home", "job": "dishwasher", "control": "stop"])
        #expect(transport.requests.allSatisfy { $0.url?.path == "/api/webhook/hook1" })

        let token = try body(transport, 0)
        #expect(token["type"] as? String == "live_activity_token")
        let tokenData = try #require(token["data"] as? [String: Any])
        #expect(tokenData["tag"] as? String == "fenton-home" && tokenData["push_token"] as? String == "ab12")
        #expect(tokenData["expires_at"] as? Double == 1_792_278_000)

        let dismissed = try body(transport, 1)
        #expect(dismissed["type"] as? String == "live_activity_dismissed")
        #expect((dismissed["data"] as? [String: Any])?["tag"] as? String == "fenton-home")

        let event = try body(transport, 2)
        #expect(event["type"] as? String == "fire_event")
        let eventData = try #require(event["data"] as? [String: Any])
        #expect(eventData["event_type"] as? String == "fenton_live_activity_action")
        #expect((eventData["event_data"] as? [String: String]) == ["tag": "fenton-home", "job": "dishwasher", "control": "stop"])
    }

    @Test func aMissingRegistrationThrows() async {
        let sender = MobileAppLiveActivityWebhook(client: MobileAppWebhookClient(
            source: FixedMobileAppWebhookSource(nil), transport: StubHTTPTransport([])))
        await #expect(throws: MobileAppWebhookError.notRegistered) { try await sender.reportDismissed(tag: "t") }
    }
}

struct StartTokenAppDataTests {
    private let config = PushConfig(json: Data(#"{"available":true,"push_url":"https://relay/api/fenton_push/apns","bundle_id":"com.sfenton.home"}"#.utf8))

    @Test func theStartTokenRidesNextToThePushDetails() {
        let data = PushAppData.resolve(config: config, token: "ab01", environment: .sandbox, startActivityToken: "cd02")
        #expect(data.json["start_live_activity_token"] as? String == "cd02")
        #expect(data.json["push_token"] as? String == "ab01")
        #expect(PushAppData.resolve(config: config, token: "ab01", environment: .sandbox).json["start_live_activity_token"] == nil)
        #expect(PushAppData.resolve(config: config, token: "ab01", environment: .sandbox, startActivityToken: "").json["start_live_activity_token"] == nil)
    }

    @Test func withoutPushDetailsThereIsNoStartToken() {
        let websocketOnly = PushAppData.resolve(config: config, token: nil, environment: .sandbox, startActivityToken: "cd02")
        #expect(websocketOnly.json.isEmpty)
        #expect(PushAppData.cleared.json.isEmpty, "sign-out removes the start token with the rest")
    }

    @Test func theUpdateRegistrationBodyCarriesIt() throws {
        let device = MobileAppDevice(marketingVersion: "1", build: "1", name: "iPhone", model: "m", osVersion: "27", deviceID: "d", apnsEnvironment: .sandbox)
        let data = PushAppData.resolve(config: config, token: "ab01", environment: .sandbox, startActivityToken: "cd02")
        let update = device.updateBody(appData: data)
        let appData = try #require((update["data"] as? [String: Any])?["app_data"] as? [String: Any])
        #expect(appData["start_live_activity_token"] as? String == "cd02")
    }
}
