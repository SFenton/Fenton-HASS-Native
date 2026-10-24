import Foundation
@testable import HassCore
import HassTestSupport
import Testing
#if canImport(UserNotifications)
import UserNotifications
#endif

// MARK: - Fixtures

private let server = HassServer(baseURL: URL(string: "https://ha.example.com")!)
private let device = MobileAppDevice(marketingVersion: "1.2.0", build: "45", name: "Stephen's iPhone", model: "iPhone18,1",
                                osVersion: "27.2", deviceID: "VENDOR-1", apnsEnvironment: .sandbox)
private let configJSON = #"{"available":true,"push_url":"http://ha.local:8123/api/fenton_push/apns","bundle_id":"com.sfenton.home","critical_alerts":false}"#

private func body(_ request: URLRequest) -> [String: Any] {
    (request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
}

// MARK: - Config and device

@Suite("Push config and device")
struct PushConfigTests {
    @Test func configParses() {
        let config = PushConfig(json: Data(configJSON.utf8))
        #expect(config.available)
        #expect(config.pushURL?.absoluteString == "http://ha.local:8123/api/fenton_push/apns")
        #expect(config.bundleID == "com.sfenton.home")
        #expect(!config.criticalAlerts)
        // Available without a URL is unavailable; junk is unavailable.
        #expect(!PushConfig(json: Data(#"{"available":true}"#.utf8)).available)
        #expect(!PushConfig(json: Data("nope".utf8)).available)
        #expect(PushConfig(json: Data(#"{"available":false,"push_url":"https://x","critical_alerts":true}"#.utf8)).criticalAlerts)
    }

    @Test func deviceBodies() throws {
        #expect(device.appVersion == "1.2.0 (45)")
        #expect(device.deviceName == "Stephen's iPhone · Fenton")
        #expect(MobileAppDevice(marketingVersion: "1", build: "1", name: "  ", model: "m", osVersion: "o", deviceID: "d",
                           apnsEnvironment: .production).deviceName == "iPhone · Fenton")
        let data = PushAppData(pushURL: URL(string: "https://relay"), pushToken: "ab01", apnsEnvironment: .sandbox)
        let registration = device.registrationBody(appData: data)
        #expect(registration["app_id"] as? String == "com.sfenton.home")
        #expect(registration["app_name"] as? String == "Fenton Home")
        #expect(registration["manufacturer"] as? String == "Apple")
        #expect(registration["os_name"] as? String == "iOS")
        #expect(registration["device_id"] as? String == "VENDOR-1")
        #expect(registration["supports_encryption"] as? Bool == false)
        let appData = try #require(registration["app_data"] as? [String: Any])
        #expect(appData["push_url"] as? String == "https://relay")
        #expect(appData["push_token"] as? String == "ab01")
        #expect(appData["apns_environment"] as? String == "sandbox")
        #expect(appData["push_websocket_channel"] == nil, "not claimed until the app listens on it")

        let update = device.updateBody(appData: .cleared)
        #expect(update["type"] as? String == "update_registration")
        let updateData = try #require(update["data"] as? [String: Any])
        #expect((updateData["app_data"] as? [String: Any])?.isEmpty == true)
        #expect(updateData["app_version"] as? String == "1.2.0 (45)")
        #expect(updateData["device_name"] as? String == "Stephen's iPhone · Fenton")
    }

    @Test func genericNamesTakeTheOwnersFirstName() {
        let generic = MobileAppDevice(marketingVersion: "1", build: "1", name: "iPhone", model: "iPhone19,2", osVersion: "27",
                                 deviceID: "d", apnsEnvironment: .sandbox)
        #expect(generic.owned(by: "Stephen Fenton").deviceName == "Stephen's iPhone · Fenton")
        #expect(generic.owned(by: nil).deviceName == "iPhone · Fenton")
        #expect(generic.owned(by: "  ").deviceName == "iPhone · Fenton")
        // A name the person chose is kept.
        #expect(device.owned(by: "Stephanie").deviceName == "Stephen's iPhone · Fenton")
    }

    @Test func appDataResolves() {
        let config = PushConfig(json: Data(configJSON.utf8))
        let push = PushAppData.resolve(config: config, token: "ff", environment: .production)
        #expect(push.pushToken == "ff")
        #expect(push.json["apns_environment"] as? String == "production")
        // No token, empty token or no relay: websocket only.
        for socketOnly in [PushAppData.resolve(config: config, token: nil, environment: .sandbox),
                           PushAppData.resolve(config: config, token: "", environment: .sandbox),
                           PushAppData.resolve(config: PushConfig(available: false), token: "ff", environment: .sandbox)] {
            #expect(socketOnly.pushURL == nil)
            #expect(socketOnly.json.isEmpty)
        }
        // A URL without a token sends no push fields.
        #expect(PushAppData(pushURL: URL(string: "https://r"), pushToken: nil, apnsEnvironment: .sandbox).json["push_url"] == nil)
        #expect(PushAppData(pushURL: URL(string: "https://r"), pushToken: "a", apnsEnvironment: nil).json["apns_environment"] == nil)
        #expect(PushAppData.cleared.json.isEmpty)
        #expect(PushAppData(pushURL: nil, pushToken: nil, apnsEnvironment: nil, websocketChannel: true).json["push_websocket_channel"] as? Bool == true)
    }

    @Test func tokenIsLowercaseHex() {
        #expect(PushToken.hex(Data([0x00, 0xAB, 0x7F, 0xFF])) == "00ab7fff")
    }

    @Test func apnsEnvironmentFromProfile() {
        let profile = { (value: String) in Data("junk<plist><key>aps-environment</key>\n\t<string>\(value)</string></plist>".utf8) }
        #expect(APNsEnvironment.detect(provisioningProfile: profile("production"), isSimulator: false) == .production)
        #expect(APNsEnvironment.detect(provisioningProfile: profile("development"), isSimulator: false) == .sandbox)
        #expect(APNsEnvironment.detect(provisioningProfile: Data("no entitlement".utf8), isSimulator: false) == .sandbox)
        #expect(APNsEnvironment.detect(provisioningProfile: nil, isSimulator: false) == .production)
        #expect(APNsEnvironment.detect(provisioningProfile: profile("production"), isSimulator: true) == .sandbox)
    }
}

// MARK: - Client

@Suite("Home Assistant push client")
struct HomeAssistantPushClientTests {
    let registration = MobileAppRegistration(server: server, userID: "u1", webhookID: "hook1")

    func client(_ transport: StubHTTPTransport) -> HomeAssistantPushClient {
        HomeAssistantPushClient(server: server, accessToken: { "ha-token" }, transport: transport)
    }

    @Test func configReadsAndMissingIntegration() async throws {
        let transport = StubHTTPTransport([(200, configJSON), (404, "")])
        let push = client(transport)
        #expect(try await push.config()?.available == true)
        #expect(try await push.config() == nil)
        #expect(transport.requests.first?.url?.path == "/api/fenton_push/config")
        #expect(transport.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer ha-token")
        await #expect(throws: PushClientError.status(500)) { try await client(StubHTTPTransport([(500, "")])).config() }
    }

    @Test func registers() async throws {
        let transport = StubHTTPTransport([(201, #"{"webhook_id":"new-hook","cloudhook_url":null}"#)])
        let id = try await client(transport).register(device, appData: PushAppData.cleared)
        #expect(id == "new-hook")
        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/api/mobile_app/registrations")
        #expect(body(request)["device_name"] as? String == "Stephen's iPhone · Fenton")
        await #expect(throws: PushClientError.unexpectedResponse) {
            try await client(StubHTTPTransport([(201, "{}")])).register(device, appData: .cleared)
        }
        await #expect(throws: PushClientError.status(400)) {
            try await client(StubHTTPTransport([(400, "")])).register(device, appData: .cleared)
        }
    }

    @Test func webhookCalls() async throws {
        let transport = StubHTTPTransport([(200, "{}"), (200, "")])
        let push = client(transport)
        try await push.updateRegistration(registration, device: device, appData: .cleared)
        try await push.fireAction(registration, event: PushActionEvent(action: "LOCK", tag: "door", replyText: "hi"))
        #expect(transport.requests.map { $0.url?.path } == ["/api/webhook/hook1", "/api/webhook/hook1"])
        // Webhooks carry no token.
        #expect(transport.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil })
        #expect(body(transport.requests[0])["type"] as? String == "update_registration")
        let fire = body(transport.requests[1])
        #expect(fire["type"] as? String == "fire_event")
        let data = try #require(fire["data"] as? [String: Any])
        #expect(data["event_type"] as? String == "mobile_app_notification_action")
        let event = try #require(data["event_data"] as? [String: Any])
        #expect(event["action"] as? String == "LOCK")
        #expect(event["tag"] as? String == "door")
        #expect(event["reply_text"] as? String == "hi")

        await #expect(throws: PushClientError.registrationGone) {
            try await client(StubHTTPTransport([(410, "")])).updateRegistration(registration, device: device, appData: .cleared)
        }
        await #expect(throws: PushClientError.status(503)) {
            try await client(StubHTTPTransport([(503, "")])).fireAction(registration, event: PushActionEvent(action: "A", tag: nil))
        }
    }

    @Test func failuresMap() async {
        let offline = StubHTTPTransport([])
        offline.error = URLError(.notConnectedToInternet)
        await #expect(throws: PushClientError.network) { try await client(offline).config() }
        let cancelled = StubHTTPTransport([])
        cancelled.error = CancellationError()
        await #expect(throws: CancellationError.self) { try await client(cancelled).config() }
        let signedOut = HomeAssistantPushClient(server: server, accessToken: { throw TokenManager.SignedOut() },
                                                transport: StubHTTPTransport([]))
        await #expect(throws: PushClientError.signedOut) { try await signedOut.config() }
        let cancelledToken = HomeAssistantPushClient(server: server, accessToken: { throw CancellationError() },
                                                     transport: StubHTTPTransport([]))
        await #expect(throws: CancellationError.self) { try await cancelledToken.config() }
    }

    @Test func eventOmitsEmptyFields() throws {
        let data = try #require(PushActionEvent(action: "OK", tag: nil).webhookBody["data"] as? [String: Any])
        #expect((data["event_data"] as? [String: Any])?.keys.sorted() == ["action"])
    }
}

// MARK: - Registrar

@Suite("Mobile app registrar")
struct MobileAppRegistrarTests {
    func registrar(_ transport: StubHTTPTransport, store: InMemoryMobileAppRegistrationStore) -> MobileAppRegistrar {
        MobileAppRegistrar(server: server,
                      client: HomeAssistantPushClient(server: server, accessToken: { "t" }, transport: transport),
                      store: store, device: device)
    }

    @Test func aSimulatorNeverRegisters() async {
        // Each simulator signs in as a real person; registering would add a device and a notify service to them.
        let transport = StubHTTPTransport([(200, configJSON), (201, #"{"webhook_id":"w1"}"#)])
        let store = InMemoryMobileAppRegistrationStore()
        let blocked = MobileAppRegistrar(server: server,
                                         client: HomeAssistantPushClient(server: server, accessToken: { "t" }, transport: transport),
                                         store: store, device: device, allowsRegistration: false)
        await #expect(throws: MobileAppRegistrar.Refusal.simulator) { try await blocked.sync(userID: "u1", token: "aa") }
        #expect(transport.requests.isEmpty)
        #expect(store.active == nil)
    }

    @Test func registrationPolicyBlocksOnlyTheSimulator() {
        #expect(MobileAppRegistrationPolicy.allowsRegistration(environment: [:], isSimulator: false))
        #expect(MobileAppRegistrationPolicy.allowsRegistration(environment: ["FENTON_MOBILE_APP_REGISTER": "1"], isSimulator: false))
        #expect(!MobileAppRegistrationPolicy.allowsRegistration(environment: [:], isSimulator: true))
        #expect(!MobileAppRegistrationPolicy.allowsRegistration(environment: ["FENTON_PUSH": "1"], isSimulator: true),
                "turning push on doesn't register a simulator")
        #expect(!MobileAppRegistrationPolicy.allowsRegistration(environment: ["FENTON_MOBILE_APP_REGISTER": "0"], isSimulator: true))
        #expect(MobileAppRegistrationPolicy.allowsRegistration(environment: ["FENTON_MOBILE_APP_REGISTER": "1"], isSimulator: true))
        #expect(!MobileAppRegistrationPolicy.isSimulator, "unit tests run on the Mac")
    }

    @Test func registersWebsocketOnlyWithoutTheIntegration() async throws {
        // 404: location and sensors still need the registration, so it goes ahead without push details.
        let transport = StubHTTPTransport([(404, ""), (201, #"{"webhook_id":"w1"}"#), (404, ""), (200, "{}")])
        let store = InMemoryMobileAppRegistrationStore()
        let shared = registrar(transport, store: store)
        let outcome = try await shared.sync(userID: "u1", token: "aa")
        guard case let .registered(registration, appData) = outcome else {
            Issue.record("expected a registration")
            return
        }
        #expect(outcome.registration == registration)
        #expect(appData == PushAppData(pushURL: nil, pushToken: nil, apnsEnvironment: nil))
        #expect(transport.requests[1].url?.path == "/api/mobile_app/registrations")
        #expect((body(transport.requests[1])["app_data"] as? [String: Any])?.isEmpty == true)
        #expect(store.active == registration)
        #expect(await store.currentWebhook() == MobileAppWebhook(server: server, webhookID: "w1"))

        // Still no integration on the next launch: the same registration is updated, not duplicated.
        let again = try await shared.sync(userID: "u1", token: "aa")
        #expect(again == .updated(registration, appData))
        #expect(again.registration == registration)
        #expect(transport.requests[3].url?.path == "/api/webhook/w1")
    }

    @Test func unavailableIntegrationIsWebsocketOnly() async throws {
        let unavailable = #"{"available":false}"#
        let transport = StubHTTPTransport([(200, unavailable), (201, #"{"webhook_id":"w"}"#)])
        guard case let .registered(_, appData) = try await registrar(transport, store: InMemoryMobileAppRegistrationStore())
            .sync(userID: "u1", token: "aa") else {
            Issue.record("expected a registration")
            return
        }
        #expect(appData.pushURL == nil)
        #expect(appData.pushToken == nil)
    }

    @Test func configFailuresStopTheSync() async {
        // A broken integration (not a missing one) must not clear working push details.
        let store = InMemoryMobileAppRegistrationStore()
        await #expect(throws: PushClientError.status(500)) {
            try await registrar(StubHTTPTransport([(500, "")]), store: store).sync(userID: "u1", token: "aa")
        }
        #expect(store.active == nil)
    }

    @Test func registersThenUpdates() async throws {
        let transport = StubHTTPTransport([(200, configJSON), (201, #"{"webhook_id":"w1"}"#), (200, configJSON), (200, "{}")])
        let store = InMemoryMobileAppRegistrationStore()
        let push = registrar(transport, store: store)
        guard case let .registered(registration, appData) = try await push.sync(userID: "u1", token: "aa") else {
            Issue.record("expected a registration")
            return
        }
        #expect(registration.webhookID == "w1")
        #expect(appData.pushToken == "aa")
        #expect(store.active == registration)
        #expect(store.registration(server: server, userID: "u1") == registration)
        guard case .updated = try await push.sync(userID: "u1", userName: "Stephen Fenton", token: "bb") else {
            Issue.record("expected an update")
            return
        }
        #expect(transport.requests.last?.url?.path == "/api/webhook/w1")
        let sent = try #require(body(transport.requests[3])["data"] as? [String: Any])
        #expect((sent["app_data"] as? [String: Any])?["push_token"] as? String == "bb")
    }

    @Test func reRegistersWhenGone() async throws {
        let saved = MobileAppRegistration(server: server, userID: "u1", webhookID: "old")
        let store = InMemoryMobileAppRegistrationStore([saved])
        let transport = StubHTTPTransport([(200, configJSON), (410, ""), (201, #"{"webhook_id":"fresh"}"#)])
        guard case let .registered(registration, _) = try await registrar(transport, store: store).sync(userID: "u1", token: nil) else {
            Issue.record("expected a new registration")
            return
        }
        #expect(registration.webhookID == "fresh")
        #expect(store.registration(server: server, userID: "u1")?.webhookID == "fresh")
    }

    @Test func otherErrorsPropagate() async {
        let store = InMemoryMobileAppRegistrationStore([MobileAppRegistration(server: server, userID: "u1", webhookID: "w")])
        await #expect(throws: PushClientError.status(500)) {
            try await registrar(StubHTTPTransport([(200, configJSON), (500, "")]), store: store).sync(userID: "u1", token: nil)
        }
        #expect(store.registration(server: server, userID: "u1") != nil)
    }

    @Test func otherBundleIsWebsocketOnly() async throws {
        let foreign = #"{"available":true,"push_url":"https://relay","bundle_id":"io.robbie.HomeAssistant"}"#
        let transport = StubHTTPTransport([(200, foreign), (201, #"{"webhook_id":"w"}"#)])
        guard case let .registered(_, appData) = try await registrar(transport, store: InMemoryMobileAppRegistrationStore())
            .sync(userID: "u1", token: "aa") else {
            Issue.record("expected a registration")
            return
        }
        #expect(appData.pushURL == nil)
    }

    @Test func signOutClearsAppData() async throws {
        let saved = MobileAppRegistration(server: server, userID: "u1", webhookID: "w1")
        let store = InMemoryMobileAppRegistrationStore([saved], active: saved)
        let transport = StubHTTPTransport([(200, "{}")])
        await registrar(transport, store: store).signOut()
        let sent = try #require(body(transport.requests[0])["data"] as? [String: Any])
        #expect((sent["app_data"] as? [String: Any])?.isEmpty == true)
        #expect(store.active == nil)
        // Kept for the next sign-in as the same user.
        #expect(store.registration(server: server, userID: "u1") == saved)

        // Nothing active, or active on another server: nothing sent.
        let idle = StubHTTPTransport([])
        await registrar(idle, store: InMemoryMobileAppRegistrationStore()).signOut()
        let elsewhere = MobileAppRegistration(server: HassServer(baseURL: URL(string: "https://other")!), userID: "u1", webhookID: "w")
        await registrar(idle, store: InMemoryMobileAppRegistrationStore([elsewhere], active: elsewhere)).signOut()
        #expect(idle.requests.isEmpty)

        // Gone: forgotten. Offline: kept.
        let goneStore = InMemoryMobileAppRegistrationStore([saved], active: saved)
        await registrar(StubHTTPTransport([(410, "")]), store: goneStore).signOut()
        #expect(goneStore.registration(server: server, userID: "u1") == nil)
        let offlineStore = InMemoryMobileAppRegistrationStore([saved], active: saved)
        await registrar(StubHTTPTransport([(503, "")]), store: offlineStore).signOut()
        #expect(offlineStore.registration(server: server, userID: "u1") == saved)
    }

    @Test func firesActions() async throws {
        let saved = MobileAppRegistration(server: server, userID: "u1", webhookID: "w1")
        let transport = StubHTTPTransport([(200, "")])
        try await registrar(transport, store: InMemoryMobileAppRegistrationStore([saved], active: saved))
            .fireAction(PushActionEvent(action: "SNOOZE", tag: "t"))
        #expect(transport.requests.first?.url?.path == "/api/webhook/w1")

        await #expect(throws: PushClientError.signedOut) {
            try await registrar(StubHTTPTransport([]), store: InMemoryMobileAppRegistrationStore()).fireAction(PushActionEvent(action: "A", tag: nil))
        }
        let goneStore = InMemoryMobileAppRegistrationStore([saved], active: saved)
        await #expect(throws: PushClientError.registrationGone) {
            try await registrar(StubHTTPTransport([(410, "")]), store: goneStore).fireAction(PushActionEvent(action: "A", tag: nil))
        }
        #expect(goneStore.active == nil)
        #expect(goneStore.registration(server: server, userID: "u1") == nil)
    }
}

// MARK: - Stores

@Suite("Mobile app registration stores")
struct MobileAppRegistrationStoreTests {
    @Test func listKeepsOnePerUser() {
        let store = InMemoryMobileAppRegistrationStore()
        let first = MobileAppRegistration(server: server, userID: "u1", webhookID: "a")
        let replaced = MobileAppRegistration(server: server, userID: "u1", webhookID: "b")
        let other = MobileAppRegistration(server: server, userID: "u2", webhookID: "c")
        store.save(first)
        store.save(replaced)
        store.save(other)
        store.setActive(replaced)
        #expect(store.registration(server: server, userID: "u1") == replaced)
        #expect(store.registration(server: server, userID: "u2") == other)
        store.remove(server: server, userID: "u2")
        #expect(store.active == replaced)
        store.remove(server: server, userID: "u1")
        #expect(store.active == nil)
        #expect(replaced.webhookURL.absoluteString == "https://ha.example.com/api/webhook/b")
    }

    @Test func storesSupplyTheActiveWebhook() async {
        let saved = MobileAppRegistration(server: server, userID: "u1", webhookID: "hook")
        let store = InMemoryMobileAppRegistrationStore([saved])
        let source: any MobileAppWebhookSource = store
        #expect(await source.currentWebhook() == nil, "saved but not signed in")
        store.setActive(saved)
        #expect(await source.currentWebhook() == saved.webhook)
        #expect(saved.webhook.url == saved.webhookURL)
        store.setActive(nil)
        #expect(await source.currentWebhook() == nil)
    }

    @Test func keychainRoundTrips() {
        let store = KeychainMobileAppRegistrationStore(service: "com.sfenton.home.push.tests.\(UUID().uuidString)")
        defer { store.remove(server: server, userID: "u1") }
        let saved = MobileAppRegistration(server: server, userID: "u1", webhookID: "kc")
        #expect(store.registration(server: server, userID: "u1") == nil)
        store.save(saved)
        store.setActive(saved)
        #expect(store.registration(server: server, userID: "u1") == saved)
        #expect(store.active == saved)
        store.remove(server: server, userID: "u1")
        #expect(store.active == nil)
        #expect(store.registration(server: server, userID: "u1") == nil)
    }

    @Test func tokenStoreRoundTripsAndFallsBack() throws {
        let service = "com.sfenton.home.auth.tests.\(UUID().uuidString)"
        let plain = KeychainTokenStore(service: service)
        // A group this test process has no entitlement for: saves fall back to an unshared item.
        let grouped = KeychainTokenStore(service: service, accessGroup: KeychainTokenStore.sharedAccessGroup)
        defer { plain.clear() }
        let credentials = StoredCredentials(server: server, refreshToken: "refresh")
        #expect(grouped.load() == nil)
        try plain.save(credentials)
        #expect(grouped.load() == credentials)
        try grouped.save(credentials)
        #expect(plain.load() == credentials)
        grouped.clear()
        #expect(plain.load() == nil)
    }
}

// MARK: - Payload

@Suite("Push payload")
struct PushPayloadTests {
    @Test func readsTheFentonBlock() throws {
        let userInfo: [AnyHashable: Any] = [
            "aps": ["alert": ["title": "Doorbell"]],
            "fenton": [
                "v": 1, "tag": "doorbell", "group": "security",
                "url": "/sfenton-react-dash/home?path=security#camera-front-door",
                "entity_id": "camera.front_door", "image": "/api/image/x", "video": "https://v/clip.mp4",
                "attachment": ["url": "https://a/file.pdf"],
                "actions": [
                    ["action": "OPEN", "title": "Open", "uri": "/sfenton-react-dash/home?path=security", "icon": "sfsymbols:door.left.hand.open"],
                    ["action": "SILENCE", "title": "Silence", "authenticationRequired": true, "destructive": true,
                     "activationMode": "foreground", "icon": "mdi:bell"],
                    ["action": "REPLY", "title": "Reply", "behavior": "textInput", "textInputButtonTitle": "Send it",
                     "textInputPlaceholder": "Say something"],
                    ["action": "", "title": "Dropped"],
                    ["title": "No id"],
                ],
                "ext": ["screen": "security"],
                "extra": ["presentation_options": ["alert", "sound"]],
            ] as [String: Any],
        ]
        let payload = try #require(PushPayload(userInfo: userInfo))
        #expect(payload.tag == "doorbell")
        #expect(payload.group == "security")
        #expect(payload.entityID == "camera.front_door")
        #expect(payload.image == "/api/image/x")
        #expect(payload.video == "https://v/clip.mp4")
        #expect(payload.attachmentURL == "https://a/file.pdf")
        #expect(payload.ext?["screen"]?.string == "security")
        #expect(payload.extra?["presentation_options"]?.array?.count == 2)
        #expect(payload.command == nil)
        #expect(payload.actions.map(\.action) == ["OPEN", "SILENCE", "REPLY"])
        let open = try #require(payload.action("OPEN"))
        #expect(open.symbol == "door.left.hand.open")
        #expect(open.activationMode == .foreground)
        let silence = try #require(payload.action("SILENCE"))
        #expect(silence.authenticationRequired && silence.destructive)
        #expect(silence.symbol == nil)
        #expect(silence.activationMode == .foreground)
        let reply = try #require(payload.action("REPLY"))
        #expect(reply.isTextInput)
        #expect(reply.activationMode == .background)
        #expect(reply.textInputButtonTitle == "Send it")
        #expect(payload.action("MISSING") == nil)
    }

    @Test func commandsAndVersions() {
        #expect(PushPayload(json: .object(["v": .number(1), "command": "clear_notification", "tag": "door"]))?.command == .clearNotification(tag: "door"))
        #expect(PushPayload(json: .object(["command": "clear_notification"]))?.command == .unsupported("clear_notification"))
        #expect(PushPayload(json: .object(["command": "request_location_update"]))?.command == .unsupported("request_location_update"))
        #expect(PushPayload(json: .object(["v": .number(2), "tag": "x"])) == nil)
        #expect(PushPayload(json: .string("nope")) == nil)
        #expect(PushPayload(userInfo: ["aps": [:]]) == nil)
        #expect(PushPayload(json: .object(["tag": ""]))?.tag == nil)
        #expect(PushAction.symbol(fromIcon: "sfsymbols: ") == nil)
    }
}

// MARK: - Links

@Suite("Push links")
struct PushLinkTests {
    @Test func dashboardLinks() {
        #expect(PushLink("/sfenton-react-dash/home?path=security#security-system") == .dashboard(path: "security", anchor: "security-system"))
        #expect(PushLink("/sfenton-react-dash/home?path=overview&user=steph&tab=auto#daily-report") == .dashboard(path: "overview", anchor: "daily-report"))
        #expect(PushLink("/sfenton-react-dash/home?route=%2Fsfenton-react-dash%2Fgarage%3Fx%3D1") == .dashboard(path: "garage", anchor: nil))
        #expect(PushLink("/sfenton-react-dash/kitchen") == .dashboard(path: "kitchen", anchor: nil))
        #expect(PushLink("/sfenton-react-dash/home") == .dashboard(path: "overview", anchor: nil))
        #expect(PushLink("/sfenton-react-dash/home?path=") == .dashboard(path: "overview", anchor: nil))
        #expect(PushLink("/") == .dashboard(path: "overview", anchor: nil))
        #expect(PushLink("https://HA.example.com/sfenton-react-dash/home?path=office", server: server) == .dashboard(path: "office", anchor: nil))
    }

    @Test func otherLinks() {
        #expect(PushLink("/config/automation/trace/automation.x") == .homeAssistant(path: "/config/automation/trace/automation.x"))
        #expect(PushLink("https://example.org/page") == .external(URL(string: "https://example.org/page")!))
        #expect(PushLink("https://ha.example.com/x") == .external(URL(string: "https://ha.example.com/x")!))
        #expect(PushLink("") == nil)
        #expect(PushLink("noAction") == nil)
        #expect(PushLink("entityId:light.kitchen") == nil)
        #expect(PushLink("http://[bad") == nil)
    }

    @Test func destinations() {
        let cases: [(String, PushDestination)] = [
            ("overview", .section(.home)), ("", .section(.home)), ("security", .section(.security)),
            ("thermostat", .section(.climate)), ("chores", .section(.chores)), ("stephs-chores", .section(.chores)),
            ("groceries", .section(.chores)), ("admin", .section(.settings)), ("to-do", .section(.settings)),
            ("master-bedroom", .homePage("master-bedroom")), ("grocery-list", .homePage("grocery-list")),
            ("all-food", .homePage("all-food")),
        ]
        for (path, destination) in cases {
            #expect(PushDestination(dashboardPath: path) == destination, "\(path)")
        }
    }
}

// MARK: - Categories and attachments

@Suite("Push categories and attachments")
struct PushCategoryTests {
    let actions = [PushAction(action: "LOCK", title: "Lock"), PushAction(action: "IGNORE", title: "Ignore", destructive: true)]

    @Test func identifierIsStable() throws {
        let category = try #require(PushCategory(actions: actions))
        #expect(category.identifier.hasPrefix("fenton.dynamic."))
        #expect(PushCategory(actions: actions)?.identifier == category.identifier)
        #expect(PushCategory(actions: [actions[0]])?.identifier != category.identifier)
        #expect(PushCategory(actions: []) == nil)
    }

    @Test func buttonsAreCappedAtWhatTheSystemPresents() throws {
        let many = (0..<6).map { PushAction(action: "A\($0)", title: "Button \($0)") }
        let category = try #require(PushCategory(actions: many))
        #expect(category.actions.map(\.action) == ["A0", "A1", "A2", "A3"])
        #expect(PushCategory(cameraActions: many).actions.count == PushCategory.maxActions)
        #if canImport(UserNotifications)
        #expect(category.notificationCategory.hiddenPreviewsBodyPlaceholder == PushCategory.hiddenPreviewsPlaceholder)
        #endif
    }

    @Test func mergeKeepsFixedAndCapsBuilt() throws {
        let category = try #require(PushCategory(actions: actions))
        let built = (0..<40).map { "fenton.dynamic.\($0)" }
        let merged = category.identifiers(merging: ["calendar"] + built + [category.identifier])
        #expect(merged.first == "calendar")
        #expect(merged.last == category.identifier)
        #expect(merged.filter { $0.hasPrefix(PushCategory.prefix) }.count == PushCategory.limit)
        #expect(!merged.contains("fenton.dynamic.0"))
    }

    #if canImport(UserNotifications)
    @Test func systemCategory() throws {
        let reply = PushAction(action: "REPLY", title: "Reply", symbol: "text.bubble", authenticationRequired: true,
                               activationMode: .foreground, isTextInput: true)
        let category = try #require(PushCategory(actions: actions + [reply]))
        let system = category.notificationCategory
        #expect(system.identifier == category.identifier)
        #expect(system.actions.map(\.identifier) == ["LOCK", "IGNORE", "REPLY"])
        #expect(system.actions[1].options.contains(.destructive))
        let text = try #require(system.actions[2] as? UNTextInputNotificationAction)
        #expect(text.textInputButtonTitle == "Send")
        #expect(text.options.contains(.authenticationRequired) && text.options.contains(.foreground))
        let existing: Set<UNNotificationCategory> = [UNNotificationCategory(identifier: "calendar", actions: [], intentIdentifiers: [])]
        #expect(Set(category.merged(into: existing).map(\.identifier)) == ["calendar", category.identifier])
    }
    #endif

    @Test func attachmentSources() {
        let camera = PushAttachmentSource.resolve(PushPayload(entityID: "camera.front_door", image: "https://x/y.png"), server: server)
        #expect(camera == PushAttachmentSource(url: URL(string: "https://ha.example.com/api/camera_proxy/camera.front_door")!,
                                              kind: .image, needsAuthorization: true))
        #expect(PushAttachmentSource.resolve(PushPayload(entityID: "lock.front", image: "/local/a.jpg"), server: server)
            == PushAttachmentSource(url: URL(string: "https://ha.example.com/local/a.jpg")!, kind: .image, needsAuthorization: true))
        #expect(PushAttachmentSource.resolve(PushPayload(video: "https://cdn.example.org/c.mp4"), server: server)
            == PushAttachmentSource(url: URL(string: "https://cdn.example.org/c.mp4")!, kind: .video, needsAuthorization: false))
        #expect(PushAttachmentSource.resolve(PushPayload(image: "ftp://nope", attachmentURL: "https://ha.example.com/f.pdf"), server: server)
            == PushAttachmentSource(url: URL(string: "https://ha.example.com/f.pdf")!, kind: .file, needsAuthorization: true))
        #expect(PushAttachmentSource.resolve(PushPayload(image: "  "), server: server) == nil)
        #expect(PushAttachmentSource.resolve(PushPayload(), server: server) == nil)
    }

    @Test func attachmentFileTypes() {
        let image = PushAttachmentSource(url: URL(string: "https://x/snap")!, kind: .image, needsAuthorization: false)
        let mimes: [(String?, String)] = [("image/jpeg", "jpg"), ("image/JPG", "jpg"), ("image/png", "png"), ("image/gif", "gif"),
                                          ("image/heic", "heic"), ("video/mp4", "mp4"), ("video/quicktime", "mov"),
                                          ("audio/mpeg", "mp3"), ("application/pdf", "pdf"), (nil, "jpg")]
        for (mime, ext) in mimes { #expect(image.fileExtension(mimeType: mime) == ext) }
        #expect(PushAttachmentSource(url: URL(string: "https://x/a.webp")!, kind: .image, needsAuthorization: false).fileExtension(mimeType: "x/y") == "webp")
        #expect(PushAttachmentSource(url: URL(string: "https://x/clip")!, kind: .video, needsAuthorization: false).fileExtension(mimeType: nil) == "mp4")
        #expect(image.byteLimit == 10_000_000)
        #expect(PushAttachmentSource(url: image.url, kind: .video, needsAuthorization: false).byteLimit == 50_000_000)
        #expect(PushAttachmentSource(url: image.url, kind: .file, needsAuthorization: false).byteLimit == 5_000_000)
    }
}

// MARK: - Enrichment

@Suite("Push enrichment")
struct PushEnrichmentTests {
    @Test func plansCategoryThreadAndAttachment() {
        let payload = PushPayload(group: "garage", actions: [PushAction(action: "CLOSE", title: "Close")], entityID: "camera.front")
        let plan = PushEnrichment(payload: payload, categoryIdentifier: PushPayload.dynamicCategory, threadIdentifier: "", server: server)
        #expect(plan.category?.actions.map(\.action) == ["CLOSE"])
        #expect(!plan.clearsPlaceholderCategory)
        #expect(plan.threadIdentifier == "garage")
        #expect(plan.attachment?.url.path == "/api/camera_proxy/camera.front")

        let plain = PushEnrichment(payload: PushPayload(group: "g"), categoryIdentifier: PushPayload.dynamicCategory,
                                   threadIdentifier: "relay-thread", server: nil)
        #expect(plain.category == nil)
        #expect(plain.clearsPlaceholderCategory)
        #expect(plain.threadIdentifier == nil, "the relay's thread wins")
        #expect(plain.attachment == nil, "no server, no attachment")
        #expect(!PushEnrichment(payload: PushPayload(), categoryIdentifier: "calendar", threadIdentifier: "", server: nil).clearsPlaceholderCategory)
    }

    @Test func cameraNotificationsUseTheFixedCameraCategory() {
        let buttons = [PushAction(action: "VIEW", title: "View", uri: "/x")]
        let camera = PushEnrichment(payload: PushPayload(actions: buttons, entityID: "camera.front"),
                                    categoryIdentifier: PushPayload.dynamicCategory, threadIdentifier: "", server: nil)
        #expect(camera.category?.identifier == PushCategory.camera)
        #expect(camera.category?.actions == buttons)
        let silent = PushEnrichment(payload: PushPayload(entityID: "camera.front"), categoryIdentifier: "", threadIdentifier: "", server: nil)
        #expect(silent.category?.identifier == PushCategory.camera, "the live view needs the category even without buttons")
        #expect(!silent.clearsPlaceholderCategory)
        // Registered once, next to the others.
        #expect(PushCategory(cameraActions: buttons).identifiers(merging: ["calendar", PushCategory.camera]) == ["calendar", PushCategory.camera])
    }

    #if canImport(UserNotifications)
    @Test func appliesToContent() {
        let content = UNMutableNotificationContent()
        content.categoryIdentifier = PushPayload.dynamicCategory
        let built = PushEnrichment(payload: PushPayload(group: "g", actions: [PushAction(action: "A", title: "A")]),
                                   categoryIdentifier: content.categoryIdentifier, threadIdentifier: "", server: nil)
        built.apply(to: content)
        #expect(content.categoryIdentifier.hasPrefix(PushCategory.prefix))
        #expect(content.threadIdentifier == "g")
        let cleared = UNMutableNotificationContent()
        cleared.categoryIdentifier = PushPayload.dynamicCategory
        PushEnrichment(payload: PushPayload(), categoryIdentifier: cleared.categoryIdentifier, threadIdentifier: "t", server: nil)
            .apply(to: cleared)
        #expect(cleared.categoryIdentifier.isEmpty)
        #expect(cleared.threadIdentifier.isEmpty)
    }
    #endif

    @Test func loaderDownloadsWithinLimits() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("push-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshot = PushAttachmentSource(url: URL(string: "https://ha.example.com/api/camera_proxy/camera.x")!, kind: .image, needsAuthorization: true)
        let transport = StubHTTPTransport([(200, "jpeg-bytes")])
        let file = try #require(await PushAttachmentLoader(transport: transport, directory: directory).load(snapshot, accessToken: "tok"))
        #expect(try String(contentsOf: file, encoding: .utf8) == "jpeg-bytes")
        #expect(file.pathExtension == "jpg")
        #expect(transport.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer tok")

        // No token for a server file, a failed status, an empty body: nothing.
        #expect(await PushAttachmentLoader(transport: StubHTTPTransport([]), directory: directory).load(snapshot, accessToken: nil) == nil)
        #expect(await PushAttachmentLoader(transport: StubHTTPTransport([(404, "x")]), directory: directory).load(snapshot, accessToken: "t") == nil)
        #expect(await PushAttachmentLoader(transport: StubHTTPTransport([(200, "")]), directory: directory).load(snapshot, accessToken: "t") == nil)
        // Over the limit.
        let file5 = PushAttachmentSource(url: URL(string: "https://cdn/x.pdf")!, kind: .file, needsAuthorization: false)
        let big = String(repeating: "x", count: 5_000_001)
        #expect(await PushAttachmentLoader(transport: StubHTTPTransport([(200, big)]), directory: directory).load(file5, accessToken: nil) == nil)
        // A public file needs no token; an unwritable folder fails.
        let open = StubHTTPTransport([(200, "pdf")])
        #expect(await PushAttachmentLoader(transport: open, directory: directory).load(file5, accessToken: nil)?.pathExtension == "pdf")
        #expect(open.requests.first?.value(forHTTPHeaderField: "Authorization") == nil)
        let missing = directory.appendingPathComponent("missing/deeper")
        #expect(await PushAttachmentLoader(transport: StubHTTPTransport([(200, "pdf")]), directory: missing).load(file5, accessToken: nil) == nil)
        #expect(PushAttachmentSource(url: snapshot.url, kind: .image, needsAuthorization: false).fileExtension(mimeType: "image/png; q=1") == "png")
    }
}

// MARK: - Trace

@Suite("Push trace")
struct PushTraceTests {
    @Test func recordsAndTrims() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("trace-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let trace = PushTrace(directory: directory)
        for index in 0..<(PushTrace.limit + 5) { trace.record("step \(index)") }
        let lines = trace.lines()
        #expect(lines.count == PushTrace.limit)
        #expect(lines.last?.hasSuffix("step \(PushTrace.limit + 4)") == true)
        // No directory: nothing recorded.
        let off = PushTrace(directory: nil)
        off.record("ignored")
        #expect(off.lines().isEmpty)
        _ = PushTrace.shared
    }

    @Test func loaderNotesNetworkFailures() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("trace-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let trace = PushTrace(directory: directory)
        let offline = StubHTTPTransport([])
        offline.error = URLError(.timedOut)
        let source = PushAttachmentSource(url: URL(string: "https://cdn/x.jpg")!, kind: .image, needsAuthorization: false)
        #expect(await PushAttachmentLoader(transport: offline, directory: directory, trace: trace).load(source, accessToken: nil) == nil)
        #expect(trace.lines().last?.contains("attachment failed: /x.jpg") == true)
    }
}

// MARK: - MJPEG

@Suite("MJPEG frame scanner")
struct MJPEGFrameScannerTests {
    let frameA = Data([0xFF, 0xD8, 0x01, 0x02, 0xFF, 0xD9])
    let frameB = Data([0xFF, 0xD8, 0x03, 0xFF, 0xD9])

    @Test func findsFramesAcrossChunks() {
        var scanner = MJPEGFrameScanner()
        let header = Data("--frame\r\nContent-Type: image/jpeg\r\n\r\n".utf8)
        let stream = header + frameA + Data("\r\n".utf8) + header + frameB + Data("\r\n".utf8)
        var frames: [Data] = []
        // Byte by byte: markers split across chunks still match.
        for byte in stream { frames += scanner.append(Data([byte])) }
        #expect(frames == [frameA, frameB])
        // Whole stream at once.
        var whole = MJPEGFrameScanner()
        #expect(whole.append(stream) == [frameA, frameB])
    }

    @Test func dropsJunkAndWaitsForTheEnd() {
        var scanner = MJPEGFrameScanner()
        #expect(scanner.append(Data([0x00, 0x11, 0xFF])).isEmpty)
        #expect(scanner.append(Data([0xD8, 0x05])).isEmpty, "a frame without its end waits")
        #expect(scanner.append(Data([0xFF, 0xD9])) == [Data([0xFF, 0xD8, 0x05, 0xFF, 0xD9])])
        // A start marker's own D8 is not taken for an end.
        #expect(scanner.append(Data([0xFF, 0xD8, 0xD9])).isEmpty)
    }

    @Test func dropsAnOversizedFrame() {
        var scanner = MJPEGFrameScanner()
        let huge = Data([0xFF, 0xD8]) + Data(repeating: 0x01, count: MJPEGFrameScanner.maxFrameBytes)
        #expect(scanner.append(huge).isEmpty)
        #expect(scanner.append(frameB) == [frameB], "resynchronizes on the next frame")
    }
}
