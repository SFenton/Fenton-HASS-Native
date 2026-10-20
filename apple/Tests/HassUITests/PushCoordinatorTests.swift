import Foundation
import HassCore
import HassTestSupport
@testable import HassUI
import SwiftUI
import Testing

/// Records what the coordinator asks of the system.
@MainActor
private final class PlatformProbe {
    var authorizationAnswer = true
    var authorizationRequests = 0
    var remoteRegistrations = 0
    var delivered: [DeliveredNotification] = []
    var removed: [[String]] = []
    var opened: [URL] = []

    var platform: PushPlatform {
        PushPlatform(
            device: { MobileAppDevice(marketingVersion: "1", build: "2", name: "Test", model: "iPhone18,1", osVersion: "27.2",
                                 deviceID: "v", apnsEnvironment: .sandbox) },
            requestAuthorization: { await MainActor.run { self.authorizationRequests += 1; return self.authorizationAnswer } },
            registerForRemoteNotifications: { self.remoteRegistrations += 1 },
            deliveredNotifications: { await MainActor.run { self.delivered } },
            removeDelivered: { ids in Task { @MainActor in self.removed.append(ids) } },
            openExternal: { self.opened.append($0) }
        )
    }
}

private let server = HassServer(baseURL: URL(string: "https://ha.example.com")!)
private let configJSON = #"{"available":true,"push_url":"https://relay/api/fenton_push/apns","bundle_id":"com.sfenton.home"}"#

private func body(_ request: URLRequest) -> [String: Any] {
    (request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
}

private func userInfo(_ fenton: [String: Any]) -> [AnyHashable: Any] {
    ["aps": ["alert": ["title": "T"]], "fenton": fenton]
}

/// Native notifications: registration on connect and token change, sign-out, taps, buttons and commands.
@MainActor
struct PushCoordinatorTests {
    @Test func registersOnConnectAndUpdatesOnToken() async throws {
        let probe = PlatformProbe()
        let transport = StubHTTPTransport([(200, configJSON), (201, #"{"webhook_id":"w1"}"#), (200, configJSON), (200, "{}")])
        let store = InMemoryMobileAppRegistrationStore()
        let push = PushCoordinator(platform: probe.platform, store: store, transport: transport)
        // Before a session there is nothing to register with.
        await push.didConnect(userID: "u1")
        #expect(transport.requests.isEmpty)

        push.sessionStarted(server: server) { "token" }
        await push.didRegister(deviceToken: Data([0xAB]))
        #expect(transport.requests.isEmpty, "a token alone waits for the user")
        await push.didConnect(userID: "u1")
        #expect(probe.authorizationRequests == 1)
        #expect(probe.remoteRegistrations == 1)
        #expect(store.active?.webhookID == "w1")
        let registration = try #require(body(transport.requests[1])["app_data"] as? [String: Any])
        #expect(registration["push_token"] as? String == "ab")

        // The same user again (a reconnect) does nothing; a new token updates.
        await push.didConnect(userID: "u1")
        await push.didRegister(deviceToken: Data([0xAB]))
        #expect(transport.requests.count == 2)
        await push.didRegister(deviceToken: Data([0xCD]))
        #expect(transport.requests.count == 4)
        #expect(transport.requests[3].url?.path == "/api/webhook/w1")
    }

    @Test func deniedPermissionStillRegistersForWebsocketPushes() async throws {
        let probe = PlatformProbe()
        probe.authorizationAnswer = false
        let transport = StubHTTPTransport([(200, configJSON), (201, #"{"webhook_id":"w1"}"#)])
        let push = PushCoordinator(platform: probe.platform, store: InMemoryMobileAppRegistrationStore(), transport: transport)
        push.sessionStarted(server: server) { "token" }
        await push.didConnect(userID: "u1")
        #expect(probe.remoteRegistrations == 0)
        let appData = try #require(body(transport.requests[1])["app_data"] as? [String: Any])
        #expect(appData["push_url"] == nil)
    }

    @Test func disabledNeverPromptsOrRegisters() async {
        let probe = PlatformProbe()
        let transport = StubHTTPTransport([])
        let push = PushCoordinator(platform: probe.platform, store: InMemoryMobileAppRegistrationStore(), transport: transport, isEnabled: false)
        push.sessionStarted(server: server) { "token" }
        await push.didConnect(userID: "u1")
        await push.didRegister(deviceToken: Data([1]))
        #expect(probe.authorizationRequests == 0)
        #expect(transport.requests.isEmpty)
        let inert = PushCoordinator.inert()
        inert.sessionStarted(server: server) { "token" }
        await inert.didConnect(userID: "u1")
        #expect(inert.pendingRequest == nil)
    }

    @Test func sessionEndClearsAppDataAndForgetsTheSession() async throws {
        let saved = MobileAppRegistration(server: server, userID: "u1", webhookID: "w1")
        let store = InMemoryMobileAppRegistrationStore([saved], active: saved)
        let transport = StubHTTPTransport([(200, "{}")])
        let push = PushCoordinator(platform: PlatformProbe().platform, store: store, transport: transport)
        push.sessionStarted(server: server) { "token" }
        push.open(link: "/sfenton-react-dash/home?path=security")
        await push.sessionEnded()
        #expect(push.pendingRequest == nil)
        #expect(store.active == nil)
        let data = try #require(body(transport.requests[0])["data"] as? [String: Any])
        #expect((data["app_data"] as? [String: Any])?.isEmpty == true)
        // Ended twice: nothing more is sent.
        await push.sessionEnded()
        #expect(transport.requests.count == 1)
    }

    @Test func tapsAndLinkButtonsOpenPages() async throws {
        let probe = PlatformProbe()
        let push = PushCoordinator(platform: probe.platform, store: InMemoryMobileAppRegistrationStore(), transport: StubHTTPTransport([]))
        push.sessionStarted(server: server) { "token" }
        let info = userInfo([
            "tag": "door", "url": "/sfenton-react-dash/home?path=security#camera-front-door",
            "actions": [["action": "OPEN_GARAGE", "title": "Garage", "uri": "/sfenton-react-dash/home?path=garage"],
                        ["action": "TRACE", "title": "Trace", "uri": "/config/automation/trace/automation.x"],
                        ["action": "WEB", "title": "Web", "uri": "https://example.org/x"]],
        ])
        await push.handle(.open, userInfo: info)
        let first = try #require(push.pendingRequest)
        #expect(first.destination == .section(.security))
        await push.handle(.action("OPEN_GARAGE", replyText: nil), userInfo: info)
        let second = try #require(push.pendingRequest)
        #expect(second.destination == .homePage("garage"))
        #expect(second.id > first.id)
        push.didOpen(first)
        #expect(push.pendingRequest == second, "a stale request does not clear a newer one")
        push.didOpen(second)
        #expect(push.pendingRequest == nil)

        await push.handle(.action("TRACE", replyText: nil), userInfo: info)
        await push.handle(.action("WEB", replyText: nil), userInfo: info)
        #expect(probe.opened.map(\.absoluteString) == ["https://ha.example.com/config/automation/trace/automation.x", "https://example.org/x"])

        // Dismissals, unknown buttons, no link, junk links and foreign notifications do nothing.
        await push.handle(.dismiss, userInfo: info)
        await push.handle(.action("MISSING", replyText: nil), userInfo: info)
        await push.handle(.open, userInfo: userInfo(["tag": "x"]))
        await push.handle(.open, userInfo: userInfo(["url": "noAction"]))
        await push.handle(.open, userInfo: ["aps": [:]])
        #expect(push.pendingRequest == nil)
        #expect(probe.opened.count == 2)
    }

    @Test func homeAssistantLinksNeedASession() {
        let probe = PlatformProbe()
        let push = PushCoordinator(platform: probe.platform, store: InMemoryMobileAppRegistrationStore(), transport: StubHTTPTransport([]))
        push.open(link: "/config/integrations")
        #expect(probe.opened.isEmpty)
    }

    @Test func buttonsFireTheNotificationActionEvent() async throws {
        let saved = MobileAppRegistration(server: server, userID: "u1", webhookID: "w1")
        let transport = StubHTTPTransport([(200, "")])
        let push = PushCoordinator(platform: PlatformProbe().platform, store: InMemoryMobileAppRegistrationStore([saved], active: saved),
                                   transport: transport)
        push.sessionStarted(server: server) { "token" }
        await push.handle(.action("REPLY", replyText: "On my way"),
                          userInfo: userInfo(["tag": "chores", "actions": [["action": "REPLY", "title": "Reply", "behavior": "textInput"]]]))
        let data = try #require(body(transport.requests[0])["data"] as? [String: Any])
        let event = try #require(data["event_data"] as? [String: Any])
        #expect(event["action"] as? String == "REPLY")
        #expect(event["tag"] as? String == "chores")
        #expect(event["reply_text"] as? String == "On my way")
    }

    @Test func clearCommandRemovesTaggedNotifications() async {
        let probe = PlatformProbe()
        probe.delivered = [DeliveredNotification(identifier: "a", tag: "door"), DeliveredNotification(identifier: "b", tag: "garage"),
                           DeliveredNotification(identifier: "c", tag: "door"), DeliveredNotification(identifier: "d", tag: nil)]
        let push = PushCoordinator(platform: probe.platform, store: InMemoryMobileAppRegistrationStore(), transport: StubHTTPTransport([]))
        #expect(await push.handleBackground(userInfo: ["aps": ["content-available": 1],
                                                        "fenton": ["v": 1, "command": "clear_notification", "tag": "door"]]))
        #expect(await push.handleBackground(userInfo: ["fenton": ["command": "clear_notification", "tag": "none"]]))
        #expect(!(await push.handleBackground(userInfo: ["fenton": ["command": "update_widgets"]])))
        #expect(!(await push.handleBackground(userInfo: ["aps": [:]])))
        await Task.yield()
        #expect(probe.removed == [["a", "c"]])
    }
}

/// Where a notification's page opens in the shell.
@MainActor
struct PushNavigationTests {
    @Test func sectionsOpenAtTheirRoot() {
        let navigator = ShellNavigator()
        navigator.paths[.security] = NavigationPath(["detail"])
        navigator.openFlyout()
        navigator.open(.section(.security))
        #expect(navigator.selection == .security)
        #expect(navigator.isAtRoot(.security))
        #expect(!navigator.isFlyoutOpen)
        for (section, expected) in [(PushSection.home, AppSection.home), (.climate, .climate), (.chores, .chores), (.settings, .settings)] {
            navigator.open(.section(section))
            #expect(navigator.selection == expected)
        }
    }

    @Test func settingsOpensTheSettingsTabAtItsRoot() {
        let navigator = ShellNavigator(selection: .chores)
        navigator.paths[.settings] = NavigationPath(["detail"])
        navigator.open(.section(.settings))
        #expect(navigator.selection == .settings)
        #expect(navigator.isAtRoot(.settings))
        #expect(navigator.accountSection == nil)
    }

    @Test func homePagesPushOnHome() {
        let navigator = ShellNavigator(selection: .climate)
        navigator.open(.homePage("garage"))
        #expect(navigator.selection == .home)
        #expect(navigator.paths[.home]?.count == 1)
        navigator.open(.homePage("all-food"))
        #expect(navigator.paths[.home]?.count == 1)
        navigator.open(.homePage("no-such-page"))
        #expect(navigator.isAtRoot(.home))
    }

    @Test func aLinkAnchorRidesTheRequest() {
        let push = PushCoordinator(platform: PlatformProbe().platform, store: InMemoryMobileAppRegistrationStore(), transport: StubHTTPTransport([]))
        push.sessionStarted(server: server) { "token" }
        push.open(link: "/sfenton-react-dash/home?path=music-room#robot-vacuum")
        #expect(push.pendingRequest?.destination == .homePage("music-room"))
        #expect(push.pendingRequest?.anchor == "robot-vacuum")
    }

    @Test func aVacuumLinkOpensItsRoomAndSheet() {
        let navigator = ShellNavigator(selection: .climate)
        navigator.open(.homePage("music-room"), anchor: "robot-vacuum")
        #expect(navigator.selection == .home)
        #expect(navigator.paths[.home]?.count == 1)
        #expect(navigator.takeSheet(forPage: "theater-room") == nil)
        #expect(navigator.takeSheet(forPage: "music-room") == "robot-vacuum")
        #expect(navigator.takeSheet(forPage: "music-room") == nil, "a sheet opens once")
        navigator.open(.homePage("music-room"), anchor: "robot-vacuum")
        navigator.open(.homePage("garage"))
        #expect(navigator.takeSheet(forPage: "music-room") == nil, "a later link without an anchor drops it")
    }

    @Test func homeRoutesForNotificationPaths() {
        #expect(HomeRoute(pushPath: "garage") == .room("garage"))
        #expect(HomeRoute(pushPath: "grocery-list") == .groceryList)
        #expect(HomeRoute(pushPath: "pantry") == .food)
        #expect(HomeRoute(pushPath: "recipes") == .food)
        #expect(HomeRoute(pushPath: "mach-e") == nil)
    }
}
