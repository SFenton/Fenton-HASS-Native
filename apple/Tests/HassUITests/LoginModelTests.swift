#if os(macOS)
import AppKit
import Foundation
import HassCore
@testable import HassUI
import SwiftUI
import Testing

/// Serves canned Home Assistant login responses keyed by request path.
final class LoginStubProtocol: URLProtocol {
    nonisolated(unsafe) static var responses: [String: [(status: Int, body: String)]] = [:]
    nonisolated(unsafe) static var failure: URLError?
    nonisolated(unsafe) static var paths: [String] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path() ?? ""
        Self.paths.append(path)
        if let failure = Self.failure {
            client?.urlProtocol(self, didFailWithError: failure)
            return
        }
        guard var queue = Self.responses[path], !queue.isEmpty else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let next = queue.removeFirst()
        Self.responses[path] = queue
        let response = HTTPURLResponse(url: request.url!, statusCode: next.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(next.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LoginStubProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func reset(_ responses: [String: [(status: Int, body: String)]] = [:]) {
        self.responses = responses
        failure = nil
        paths = []
    }
}

/// Every suite that shares the login stub or sets launch environment runs one after another: Swift Testing runs separate suites
/// in parallel, and these share `LoginStubProtocol`'s answers and the process environment.
@Suite(.serialized)
enum LoginTests {}

extension LoginTests {
/// The sign-in flow behind the Sign In button on a stubbed Home Assistant, and the account the app remembers.
@MainActor
@Suite(.serialized)
struct LoginModelTests {
    static let tokenBody = #"{"access_token":"A","expires_in":1800,"refresh_token":"R","token_type":"Bearer"}"#
    static let start = #"{"flow_id":"f1","type":"form","step_id":"init"}"#
    static let granted: [String: [(status: Int, body: String)]] = [
        "/auth/login_flow": [(200, start)],
        "/auth/login_flow/f1": [(200, #"{"type":"create_entry","result":"CODE"}"#)],
        "/auth/token": [(200, tokenBody)],
    ]

    /// A throwaway place for the remembered account.
    func store() throws -> (RememberedAccountStore, UserDefaults) {
        let defaults = try #require(UserDefaults(suiteName: "login.tests.\(UUID())"))
        return (RememberedAccountStore(defaults: defaults), defaults)
    }

    /// A model whose flow talks to `responses`.
    func stubbed(_ responses: [String: [(status: Int, body: String)]], mode: LoginModel.Mode = .fresh,
                 store: RememberedAccountStore? = nil) throws -> LoginModel {
        LoginStubProtocol.reset(responses)
        return LoginModel(mode: mode, store: try store ?? self.store().0) { HassLoginFlow(server: $0, session: LoginStubProtocol.session()) }
    }

    /// Signs in on `model` and returns what the screen's callback received.
    func signIn(_ model: LoginModel) async -> (HassServer, AuthTokens)? {
        var received: (HassServer, AuthTokens)?
        await model.submit { server, tokens in received = (server, tokens) }?.value
        return received
    }

    // MARK: Fields

    @Test func signInNeedsAUsernameAndAPasswordAndTheServerIsFixed() throws {
        let model = LoginModel(store: try store().0)
        #expect(model.server == HassServer.fentonHome, "there is no address to type")
        #expect(!model.canSubmit)
        model.username = "stephen"
        #expect(!model.canSubmit)
        model.password = "pw"
        #expect(model.canSubmit)
        model.username = "   "
        #expect(!model.canSubmit, "a blank username is nothing")
        #expect(model.submit { _, _ in } == nil)
        #expect(!model.isWorking, "nothing was sent")
    }

    @Test func aFreshSignInStartsWithTheLastUsernameAndNeverThePassword() throws {
        let (store, _) = try store()
        #expect(LoginModel(store: store).username.isEmpty)
        store.remember(username: "stephen")
        let model = LoginModel(store: store)
        #expect(model.username == "stephen" && model.password.isEmpty)
    }

    @Test func aDebugLaunchPrefillsFromTheEnvironment() throws {
        let model = LoginModel(store: try store().0)
        model.prefillForDebugTesting([:])
        #expect(model.username.isEmpty && model.password.isEmpty)
        model.prefillForDebugTesting(["FENTON_HASS_SERVER": "https://ha.test", "FENTON_HASS_USERNAME": "u", "FENTON_HASS_PASSWORD": "p"])
        #expect(model.server.baseURL.absoluteString == "https://ha.test" && model.username == "u" && model.password == "p")
        model.prefillForDebugTesting()
    }

    // MARK: Sign in

    @Test func aSuccessfulSignInHandsOverTokensRemembersTheNameAndForgetsThePassword() async throws {
        let (store, _) = try store()
        let model = try stubbed(Self.granted, store: store)
        model.username = " stephen "
        model.password = "pw"
        let task = try #require(model.submit { _, _ in })
        #expect(model.isWorking && !model.canSubmit, "Sign In is off while the request runs")
        #expect(model.busyValue == "Signing In" && model.buttonTitle == "Signing In…")
        await task.value
        #expect(!model.isWorking && model.busyValue.isEmpty && model.buttonTitle == "Sign In")
        #expect(model.password.isEmpty, "the password is cleared once sign-in succeeds")
        #expect(model.failure == nil)
        #expect(store.username == "stephen", "the trimmed username is kept for next time")

        let again = try stubbed(Self.granted)
        again.username = "stephen"
        again.password = "pw"
        let (server, tokens) = try #require(await signIn(again))
        #expect(server == HassServer.fentonHome)
        #expect(tokens.accessToken == "A" && tokens.refreshToken == "R")
    }

    @Test func aWrongPasswordIsSaidPlainlyClearsThePasswordAndKeepsTheUsername() async throws {
        let (store, _) = try store()
        let model = try stubbed([
            "/auth/login_flow": [(200, Self.start)],
            "/auth/login_flow/f1": [(200, #"{"type":"form","step_id":"init","errors":{"base":"invalid_auth"}}"#)],
        ], store: store)
        model.username = "stephen"
        model.password = "wrong"
        let token = model.passwordFocusToken
        #expect(await signIn(model) == nil)
        #expect(model.failure == .wrongCredentials)
        #expect(model.failure?.inlineMessage == "That username and password don't match. Check them and try again.")
        #expect(model.failure?.cardTitle == nil && model.failure?.detail == nil)
        #expect(model.password.isEmpty && model.username == "stephen")
        #expect(model.passwordFocusToken == token + 1, "the password field takes focus")
        #expect(model.buttonTitle == "Sign In")
        #expect(!model.canSubmit, "the password is retyped before trying again")
        #expect(store.username == nil, "a refused sign-in remembers nothing")
        model.password = "right"
        #expect(model.canSubmit)
    }

    @Test func aServerThatCannotBeReachedGetsACardAndKeepsTheFields() async throws {
        let model = try stubbed([:])
        LoginStubProtocol.failure = URLError(.notConnectedToInternet)
        model.username = "stephen"
        model.password = "pw"
        #expect(await signIn(model) == nil)
        guard case let .unreachable(detail)? = model.failure else { Issue.record("expected unreachable, got \(String(describing: model.failure))"); return }
        #expect(!detail.isEmpty && model.failure?.detail == detail, "the raw reason is one tap away")
        #expect(model.failure?.cardTitle == "Can't reach Home right now")
        #expect(model.failure?.cardBody == "Check that this phone is online. If it is, Home Assistant may be restarting; try again in a minute.")
        #expect(model.failure?.inlineMessage == nil)
        #expect(model.buttonTitle == "Try Again")
        #expect(model.username == "stephen" && model.password == "pw", "the fields keep their values")
        #expect(model.canSubmit)
    }

    @Test func aGatewayErrorReadsAsUnreachableWithItsCode() async throws {
        let model = try stubbed(["/auth/login_flow": [(502, "Bad gateway")]])
        model.username = "stephen"
        model.password = "pw"
        #expect(await signIn(model) == nil)
        #expect(model.failure == .unreachable(detail: "HTTP 502"))
    }

    @Test func anythingElseGetsTheOtherCardWithItsReason() async throws {
        let model = try stubbed([
            "/auth/login_flow": [(200, Self.start)],
            "/auth/login_flow/f1": [(200, #"{"type":"abort","reason":"too_many_attempts"}"#)],
        ])
        model.username = "stephen"
        model.password = "pw"
        #expect(await signIn(model) == nil)
        #expect(model.failure == .failed(detail: "flow aborted: too_many_attempts"))
        #expect(model.failure?.cardTitle == "Sign-in didn't work")
        #expect(model.failure?.cardBody?.hasPrefix("Something went wrong") == true)
        #expect(model.buttonTitle == "Try Again")
        #expect(model.password == "pw")
        #expect(LoginModel.failure(for: HassLoginFlow.LoginError.invalidCode) == .failed(detail: "invalid code"))
        struct Odd: LocalizedError { var errorDescription: String? { "odd" } }
        #expect(LoginModel.failure(for: Odd()) == .failed(detail: "odd"))
        #expect(LoginModel.Failure.failed(detail: "").detail == nil, "an empty reason has no Details")
    }

    @Test func anAccountWithTwoStepSignInIsToldItIsNotSupported() async throws {
        let model = try stubbed([
            "/auth/login_flow": [(200, Self.start)],
            "/auth/login_flow/f1": [(200, #"{"type":"form","step_id":"mfa","errors":{}}"#)],
        ])
        model.username = "stephen"
        model.password = "pw"
        #expect(await signIn(model) == nil)
        #expect(model.failure == .twoStepUnsupported)
        #expect(model.failure?.inlineMessage == "Two-step sign-in isn't supported. Turn it off for this account in Home Assistant.")
        #expect(model.failure?.announcement == model.failure?.inlineMessage)
        #expect(model.password == "pw" && model.buttonTitle == "Sign In")
    }

    @Test func aCardIsAnnouncedByItsTitleAndBody() {
        let failure = LoginModel.Failure.unreachable(detail: "HTTP 502")
        #expect(failure.announcement == "Can't reach Home right now. Check that this phone is online. If it is, Home Assistant may be restarting; try again in a minute.")
    }

    @Test func aCallbackThatThrowsLeavesTheOtherCardWithItsMessage() async throws {
        struct SaveFailed: LocalizedError { var errorDescription: String? { "Couldn't save the sign-in." } }
        let (store, _) = try store()
        let model = try stubbed(Self.granted, store: store)
        model.username = "stephen"
        model.password = "pw"
        await model.submit { _, _ in throw SaveFailed() }?.value
        #expect(model.failure == .failed(detail: "Couldn't save the sign-in."))
    }

    @Test func eachAttemptStartsAFreshFlow() async throws {
        let model = try stubbed([
            "/auth/login_flow": [(200, Self.start), (200, Self.start)],
            "/auth/login_flow/f1": [
                (200, #"{"type":"form","step_id":"init","errors":{"base":"invalid_auth"}}"#),
                (200, #"{"type":"create_entry","result":"CODE"}"#),
            ],
            "/auth/token": [(200, Self.tokenBody)],
        ])
        model.username = "stephen"
        model.password = "wrong"
        #expect(await signIn(model) == nil)
        model.password = "right"
        #expect(await signIn(model) != nil)
        #expect(LoginStubProtocol.paths.filter { $0 == "/auth/login_flow" }.count == 2)
    }

    // MARK: Welcome back

    @Test func aSessionThatEndedKnowsTheAccountAndCanLeaveIt() throws {
        let (store, defaults) = try store()
        store.remember(username: "stephen")
        defaults.set("Stephen Fenton", forKey: RememberedAccountStore.nameKey)
        let account = try #require(store.account)
        let model = LoginModel(mode: .welcomeBack(account), store: store)
        #expect(model.username == "stephen" && model.mode == .welcomeBack(account))
        model.password = "pw"
        #expect(model.canSubmit, "the password alone is asked for")
        model.useDifferentAccount()
        #expect(model.mode == .fresh && model.username.isEmpty && model.password.isEmpty)
        #expect(store.account == nil, "the account is forgotten")
    }

    // MARK: Debug stub

    @Test func aDebugLaunchCanAskForACannedAnswer() async throws {
        #expect(DebugSignInStub.mode([:]) == nil && DebugSignInStub.session([:]) == nil)
        #expect(DebugSignInStub.mode(["FENTON_SIGNIN_STUB": "nonsense"]) == nil)
        for (mode, expected): (String, LoginModel.Failure) in [
            ("wrong", .wrongCredentials),
            ("failed", .failed(detail: "flow aborted: too_many_attempts")),
            ("twostep", .twoStepUnsupported),
        ] {
            let session = try #require(DebugSignInStub.session(["FENTON_SIGNIN_STUB": mode]))
            let model = LoginModel(store: try store().0) { HassLoginFlow(server: $0, session: session) }
            model.username = "u"
            model.password = "p"
            #expect(await signIn(model) == nil)
            #expect(model.failure == expected, "\(mode)")
        }
        let offline = try #require(DebugSignInStub.session(["FENTON_SIGNIN_STUB": "unreachable"]))
        let model = LoginModel(store: try store().0) { HassLoginFlow(server: $0, session: offline) }
        model.username = "u"
        model.password = "p"
        #expect(await signIn(model) == nil)
        guard case .unreachable? = model.failure else { Issue.record("expected unreachable"); return }
        _ = LoginModel.defaultFlow(.fentonHome)
    }

    @Test func aSlowStubAnswersAfterTheBusyStateHasShown() async throws {
        let session = try #require(DebugSignInStub.session(["FENTON_SIGNIN_STUB": "slow"]))
        let model = LoginModel(store: try store().0) { HassLoginFlow(server: $0, session: session) }
        model.username = "u"
        model.password = "p"
        let task = try #require(model.submit { _, _ in })
        #expect(model.isWorking)
        await task.value
        #expect(model.failure == .wrongCredentials)
    }
}

/// The screen over a model, in each state it reaches.
@MainActor
@Suite(.serialized)
struct LoginViewTests {
    static let phone = CGSize(width: 402, height: 874)
    static let tablet = CGSize(width: 1180, height: 820)

    func model(_ mode: LoginModel.Mode = .fresh) throws -> LoginModel {
        let defaults = try #require(UserDefaults(suiteName: "login.view.tests.\(UUID())"))
        return LoginModel(mode: mode, store: RememberedAccountStore(defaults: defaults))
    }

    func draw(_ model: LoginModel, size: CGSize = phone, intro: Bool = false) async throws -> NSBitmapImageRep {
        let hosted = HostedWindow(LoginView(model: model, playsIntro: intro) { _, _ in }, size: size)
        defer { hosted.close() }
        await hosted.settle(intro ? 1.8 : 0.6)
        return try #require(hosted.snapshot())
    }

    func failing(_ body: String, status: Int = 200) throws -> LoginModel {
        LoginStubProtocol.reset(["/auth/login_flow": [(200, #"{"flow_id":"f","type":"form","step_id":"init"}"#)],
                                 "/auth/login_flow/f": [(status, body)]])
        let defaults = try #require(UserDefaults(suiteName: "login.view.tests.\(UUID())"))
        let model = LoginModel(store: RememberedAccountStore(defaults: defaults)) { HassLoginFlow(server: $0, session: LoginStubProtocol.session()) }
        model.username = "stephen"
        model.password = "wrong"
        return model
    }

    @Test func theScreenDrawsEachStateTheFlowReaches() async throws {
        let empty = try await draw(model())
        #expect(empty.distinctColors > 20, "the glow, the mark and the module")
        let filled = try model()
        filled.username = "stephen"
        filled.password = "secret"
        let ready = try await draw(filled)
        #expect(ready.differs(from: empty), "typed fields change the form")

        let wrong = try failing(#"{"type":"form","step_id":"init","errors":{"base":"x"}}"#)
        await wrong.submit { _, _ in }?.value
        let refused = try await draw(wrong)
        #expect(refused.differs(from: ready), "the red line and the password row's hairline appear")

        let offline = try failing(#"{"type":"abort","reason":"too_many_attempts"}"#)
        await offline.submit { _, _ in }?.value
        let card = try await draw(offline)
        #expect(card.differs(from: refused), "the red card appears above the fields")

        let account = RememberedAccount(username: "stephen", name: "Stephen Fenton")
        let welcome = try await draw(model(.welcomeBack(account)))
        #expect(welcome.differs(from: empty), "the monogram and one field replace the mark and two")
    }

    @Test func whileARequestIsOutTheButtonShowsItsSpinner() async throws {
        let idle = try model()
        idle.username = "stephen"
        idle.password = "pw"
        let resting = try await draw(idle)
        let defaults = try #require(UserDefaults(suiteName: "login.view.tests.\(UUID())"))
        let slow = try #require(DebugSignInStub.session(["FENTON_SIGNIN_STUB": "slow"]))
        let working = LoginModel(store: RememberedAccountStore(defaults: defaults)) { HassLoginFlow(server: $0, session: slow) }
        working.username = "stephen"
        working.password = "pw"
        let task = working.submit { _, _ in }
        let busy = try await draw(working)
        #expect(busy.differs(from: resting), "the fields dim and the arc turns in the button")
        await task?.value
    }

    @Test func theFormIsAColumnOnATabletAndTheIntroLandsOnTheSameScreen() async throws {
        let wide = try await draw(model(), size: Self.tablet)
        #expect(wide.distinctColors > 20)
        let withIntro = try await draw(model(), intro: true)
        let without = try await draw(model())
        #expect(withIntro.distinctColors > 20 && without.distinctColors > 20, "the intro ends on the finished screen")
    }
}

/// The screen's controls, pressed through the accessibility tree.
@MainActor
@Suite(.serialized, .enabled(if: AXWindow.isAvailable, "Needs accessibility permission for the test host"))
struct LoginFlowTests {
    func model(_ mode: LoginModel.Mode = .fresh, flow: @escaping (HassServer) -> HassLoginFlow) throws -> LoginModel {
        let defaults = try #require(UserDefaults(suiteName: "login.flow.tests.\(UUID())"))
        return LoginModel(mode: mode, store: RememberedAccountStore(defaults: defaults), makeFlow: flow)
    }

    /// A field takes typed text once it has the keyboard, so it is pressed first (a window's first click only wakes it), and
    /// both are tried again while a loaded Mac catches up.
    func enter(_ text: String, into id: String, in driver: AXWindow, until check: @escaping () -> Bool) async -> Bool {
        for _ in 0..<5 {
            _ = await driver.press(id)
            await driver.window.settle(0.3)
            if await driver.type(text, into: id, attempts: 1, until: { _ in check() }) { return true }
        }
        return false
    }

    @Test func typingBothFieldsEnablesSignInAndPressingItSignsIn() async throws {
        LoginStubProtocol.reset(LoginModelTests.granted)
        let model = try model { HassLoginFlow(server: $0, session: LoginStubProtocol.session()) }
        var received: AuthTokens?
        let driver = AXWindow(LoginView(model: model) { _, tokens in received = tokens }, size: LoginViewTests.phone)
        defer { driver.close() }
        let nodes = await driver.wait { $0.contains { $0.identifier == "login.submit" } }
        for id in ["login.username", "login.password", "login.submit", "login.title", "login.footnote"] {
            #expect(nodes.contains { $0.identifier == id }, "\(id)")
        }
        #expect(!nodes.contains { $0.identifier == "login.server" || $0.identifier == "login.code" }, "no address and no code field")
        #expect(nodes.first { $0.identifier == "login.submit" }?.isEnabled == false, "Sign In waits for both fields")
        #expect(await enter("stephen", into: "login.username", in: driver) { model.username == "stephen" })
        #expect(await enter("pw", into: "login.password", in: driver) { model.password == "pw" })
        #expect(await driver.press("login.submit") { _ in received != nil })
        #expect(received?.refreshToken == "R")
    }

    @Test func aRefusedPasswordShowsItsLineAndAnUnreachableServerItsCardWithDetails() async throws {
        LoginStubProtocol.reset(["/auth/login_flow": [(200, LoginModelTests.start)],
                                 "/auth/login_flow/f1": [(200, #"{"type":"form","step_id":"init","errors":{"base":"invalid_auth"}}"#)]])
        let refused = try model { HassLoginFlow(server: $0, session: LoginStubProtocol.session()) }
        refused.username = "stephen"
        refused.password = "wrong"
        let driver = AXWindow(LoginView(model: refused) { _, _ in }, size: LoginViewTests.phone)
        defer { driver.close() }
        #expect(await driver.press("login.submit") { $0.contains { $0.identifier == "login.error" } })
        let line = await driver.text("login.error")
        #expect(line?.contains("don't match") == true)

        LoginStubProtocol.reset()
        LoginStubProtocol.failure = URLError(.notConnectedToInternet)
        let offline = try model { HassLoginFlow(server: $0, session: LoginStubProtocol.session()) }
        offline.username = "stephen"
        offline.password = "pw"
        let second = AXWindow(LoginView(model: offline) { _, _ in }, size: LoginViewTests.phone)
        defer { second.close() }
        #expect(await second.press("login.submit") { $0.contains { $0.identifier == "login.error.card" } })
        let nodes = await second.wait { $0.contains { $0.identifier == "login.error.details" } }
        #expect(nodes.contains { $0.identifier == "login.error.details" }, "Details is offered")
        #expect(nodes.first { $0.identifier == "login.submit" }?.spoken.contains("Try Again") == true || offline.buttonTitle == "Try Again")
    }

    @Test func theWelcomeBackScreenShowsTheAccountAndOnePasswordFieldAndLetsGo() async throws {
        let account = RememberedAccount(username: "stephen", name: "Stephen Fenton")
        let model = try model(.welcomeBack(account)) { HassLoginFlow(server: $0) }
        var left = false
        let driver = AXWindow(LoginView(model: model, onUseDifferentAccount: { left = true }) { _, _ in }, size: LoginViewTests.phone)
        defer { driver.close() }
        let nodes = await driver.wait { $0.contains { $0.identifier == "login.differentAccount" } }
        #expect(nodes.contains { $0.identifier == "login.username.readonly" && ($0.label + $0.value).contains("stephen") })
        #expect(!nodes.contains { $0.identifier == "login.username" }, "the account is shown, not asked for")
        #expect(nodes.contains { $0.identifier == "login.password" })
        #expect(nodes.contains { $0.identifier == "login.title" && ($0.value + $0.label + $0.title).contains("Welcome back, Stephen") })
        #expect(await driver.press("login.differentAccount") { _ in left })
        let fresh = await driver.wait { $0.contains { $0.identifier == "login.username" } }
        #expect(fresh.contains { $0.identifier == "login.username" }, "Use a Different Account asks for the username again")
        #expect(model.mode == .fresh)
    }
}
}
#endif
