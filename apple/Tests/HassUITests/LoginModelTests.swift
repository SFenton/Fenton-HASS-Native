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

/// The sign-in flow behind the Sign In button on a stubbed Home Assistant, and the screen in each state it reaches.
@MainActor
@Suite(.serialized)
struct LoginModelTests {
    static let tokenBody = #"{"access_token":"A","expires_in":1800,"refresh_token":"R","token_type":"Bearer"}"#
    static let phone = CGSize(width: 402, height: 874)

    /// A model whose flow talks to `responses`.
    func stubbed(_ responses: [String: [(status: Int, body: String)]]) -> LoginModel {
        LoginStubProtocol.reset(responses)
        return LoginModel { HassLoginFlow(server: $0, session: LoginStubProtocol.session()) }
    }

    /// Signs in on `model` and returns what the screen's callback received.
    func signIn(_ model: LoginModel) async -> (HassServer, AuthTokens)? {
        var received: (HassServer, AuthTokens)?
        await model.submit { server, tokens in received = (server, tokens) }?.value
        return received
    }

    // MARK: Fields

    @Test func signInNeedsAUsernameAPasswordAndAnAddress() {
        let model = LoginModel()
        #expect(model.serverText == HassServer.fentonHome.baseURL.absoluteString)
        #expect(!model.canSubmit)
        model.username = "stephen"
        #expect(!model.canSubmit)
        model.password = "pw"
        #expect(model.canSubmit)
        model.serverText = ""
        #expect(!model.canSubmit, "an empty address can't be submitted")
        #expect(model.submit { _, _ in } == nil)
        #expect(!model.isWorking)
        model.serverText = "https://ha.example.com"
        #expect(model.canSubmit)
    }

    @Test func returnInTheAddressFieldAddsNoLine() {
        let model = LoginModel()
        model.serverText = "https://ha.example.com\n"
        model.stripNewlines()
        #expect(model.serverText == "https://ha.example.com")
        model.stripNewlines()
        #expect(model.serverText == "https://ha.example.com", "nothing to strip")
    }

    @Test func aDebugLaunchPrefillsFromTheEnvironment() {
        let model = LoginModel()
        model.prefillForDebugTesting([:])
        #expect(model.username.isEmpty && model.password.isEmpty)
        model.prefillForDebugTesting(["FENTON_HASS_SERVER": "https://ha.test", "FENTON_HASS_USERNAME": "u", "FENTON_HASS_PASSWORD": "p"])
        #expect(model.serverText == "https://ha.test" && model.username == "u" && model.password == "p")
        model.prefillForDebugTesting()
    }

    // MARK: Sign in

    @Test func aSuccessfulSignInHandsOverTokensAndForgetsThePassword() async throws {
        let model = stubbed([
            "/auth/login_flow": [(200, #"{"flow_id":"f1","type":"form","step_id":"init"}"#)],
            "/auth/login_flow/f1": [(200, #"{"type":"create_entry","result":"CODE"}"#)],
            "/auth/token": [(200, Self.tokenBody)],
        ])
        model.serverText = " https://ha.example.com "
        model.username = "stephen"
        model.password = "pw"
        let task = try #require(model.submit { _, _ in })
        #expect(model.isWorking && !model.canSubmit, "Sign In is off while the request runs")
        #expect(model.busyValue == "Signing In")
        await task.value
        #expect(!model.isWorking && model.busyValue.isEmpty)
        #expect(model.password.isEmpty, "the password is cleared once sign-in succeeds")
        #expect(model.errorMessage == nil)

        let again = stubbed([
            "/auth/login_flow": [(200, #"{"flow_id":"f1","type":"form","step_id":"init"}"#)],
            "/auth/login_flow/f1": [(200, #"{"type":"create_entry","result":"CODE"}"#)],
            "/auth/token": [(200, Self.tokenBody)],
        ])
        again.serverText = "https://ha.example.com"
        again.username = "stephen"
        again.password = "pw"
        let (server, tokens) = try #require(await signIn(again))
        #expect(server.baseURL.absoluteString == "https://ha.example.com")
        #expect(tokens.accessToken == "A" && tokens.refreshToken == "R")
    }

    @Test func aTwoFactorAccountAsksForTheCodeThenVerifies() async throws {
        let model = stubbed([
            "/auth/login_flow": [(200, #"{"flow_id":"f2","type":"form","step_id":"init"}"#)],
            "/auth/login_flow/f2": [
                (200, #"{"type":"form","step_id":"mfa","errors":{}}"#),
                (200, #"{"type":"form","step_id":"mfa","errors":{"base":"invalid_code"}}"#),
                (200, #"{"type":"create_entry","result":"CODE2"}"#),
            ],
            "/auth/token": [(200, Self.tokenBody)],
        ])
        model.username = "stephen"
        model.password = "pw"
        #expect(await signIn(model) == nil)
        #expect(model.needsMFA && model.errorMessage == nil)
        #expect(!model.canSubmit, "Verify needs a code")
        model.mfaCode = "000000"
        #expect(model.canSubmit)
        #expect(await signIn(model) == nil)
        #expect(model.needsMFA, "a wrong code keeps the second step")
        #expect(model.errorMessage == LoginModel.message(for: .invalidCode) || model.errorMessage == LoginModel.message(for: .invalidCredentials))
        model.mfaCode = "123456"
        #expect(model.busyValue.isEmpty)
        let result = await signIn(model)
        #expect(result?.1.refreshToken == "R")
    }

    @Test func aWrongPasswordShowsItsMessageAndKeepsTheForm() async {
        let model = stubbed([
            "/auth/login_flow": [(200, #"{"flow_id":"f3","type":"form","step_id":"init"}"#)],
            "/auth/login_flow/f3": [(200, #"{"type":"form","step_id":"init","errors":{"base":"invalid_auth"}}"#)],
        ])
        model.username = "stephen"
        model.password = "wrong"
        #expect(await signIn(model) == nil)
        #expect(model.errorMessage == "Incorrect username or password.")
        #expect(!model.needsMFA && model.password == "wrong")
        #expect(model.canSubmit, "the person can correct it and try again")
    }

    @Test func anUnreachableServerIsReportedWithItsReason() async {
        let model = stubbed([:])
        LoginStubProtocol.failure = URLError(.notConnectedToInternet)
        model.username = "stephen"
        model.password = "pw"
        #expect(await signIn(model) == nil)
        #expect(model.errorMessage?.hasPrefix("Couldn't reach the server (") == true)
    }

    @Test func anUnexpectedAnswerStartsTheFlowOver() async {
        let model = stubbed([
            "/auth/login_flow": [(200, #"{"flow_id":"f4","type":"form","step_id":"init"}"#)],
            "/auth/login_flow/f4": [(200, #"{"type":"abort","reason":"too_many_attempts"}"#)],
        ])
        model.username = "stephen"
        model.password = "pw"
        #expect(await signIn(model) == nil)
        #expect(model.errorMessage == "Sign-in failed (flow aborted: too_many_attempts). Try again.")
        #expect(!model.needsMFA && model.mfaCode.isEmpty)
        #expect(LoginModel.message(for: .network("timeout")) == "Couldn't reach the server (timeout).")
        #expect(LoginModel.message(for: .invalidCode) == "That code didn't work. Try the current one.")
    }

    @Test func aCallbackThatThrowsLeavesAMessageAndResets() async {
        struct SaveFailed: LocalizedError { var errorDescription: String? { "Couldn't save the sign-in." } }
        let model = stubbed([
            "/auth/login_flow": [(200, #"{"flow_id":"f5","type":"form","step_id":"init"}"#)],
            "/auth/login_flow/f5": [(200, #"{"type":"create_entry","result":"CODE"}"#)],
            "/auth/token": [(200, Self.tokenBody)],
        ])
        model.username = "stephen"
        model.password = "pw"
        await model.submit { _, _ in throw SaveFailed() }?.value
        #expect(model.errorMessage == "Couldn't save the sign-in.")
        #expect(!model.needsMFA)
    }

    // MARK: Screen

    @Test func theScreenDrawsEachStateTheFlowReaches() async throws {
        func draw(_ model: LoginModel) async throws -> NSBitmapImageRep {
            let hosted = HostedWindow(LoginView(model: model) { _, _ in }, size: Self.phone)
            defer { hosted.close() }
            await hosted.settle(0.5)
            return try #require(hosted.snapshot())
        }
        let empty = try await draw(LoginModel())
        let filled = LoginModel()
        filled.username = "stephen"
        filled.password = "secret"
        let ready = try await draw(filled)
        #expect(ready.differs(from: empty), "typed fields change the form")

        let failing = stubbed(["/auth/login_flow": [(200, #"{"flow_id":"f","type":"form","step_id":"init"}"#)],
                               "/auth/login_flow/f": [(200, #"{"type":"form","step_id":"init","errors":{"base":"x"}}"#)]])
        failing.username = "stephen"
        failing.password = "wrong"
        await failing.submit { _, _ in }?.value
        let error = try await draw(failing)
        #expect(error.differs(from: ready), "the error row appears")

        let mfa = stubbed(["/auth/login_flow": [(200, #"{"flow_id":"f","type":"form","step_id":"init"}"#)],
                           "/auth/login_flow/f": [(200, #"{"type":"form","step_id":"mfa","errors":{}}"#)]])
        mfa.username = "stephen"
        mfa.password = "pw"
        await mfa.submit { _, _ in }?.value
        let code = try await draw(mfa)
        #expect(code.differs(from: ready), "the code field replaces the account fields")

        // While a request is out the button shows its spinner.
        let slow = stubbed(["/auth/login_flow": [(200, #"{"flow_id":"f","type":"form","step_id":"init"}"#)]])
        slow.username = "stephen"
        slow.password = "pw"
        let task = slow.submit { _, _ in }
        let working = try await draw(slow)
        #expect(working.distinctColors > 3)
        await task?.value
    }
}

#endif
