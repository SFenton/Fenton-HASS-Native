import Foundation
import HassCore
import Observation

/// What the sign-in screen holds and does: the fields, the MFA step, the in-flight state and the Home Assistant
/// login flow behind Sign In (kept apart from ``LoginView`` so the flow is tested without a window).
@MainActor
@Observable
final class LoginModel {
    /// The server's address as typed.
    var serverText = HassServer.fentonHome.baseURL.absoluteString
    /// The account name.
    var username = ""
    /// The password. Cleared once sign-in succeeds; never stored.
    var password = ""
    /// The authenticator code, on the second step.
    var mfaCode = ""
    /// Whether the flow asked for a two-factor code.
    private(set) var needsMFA = false
    /// Whether a request is in flight.
    private(set) var isWorking = false
    /// What went wrong, for the screen to show.
    private(set) var errorMessage: String?

    @ObservationIgnored private var flow: HassLoginFlow?
    @ObservationIgnored private let makeFlow: (HassServer) -> HassLoginFlow

    /// Creates the model.
    /// - Parameter makeFlow: Builds the login flow for a server; tests pass one on a stubbed session.
    init(makeFlow: @escaping (HassServer) -> HassLoginFlow = { HassLoginFlow(server: $0) }) {
        self.makeFlow = makeFlow
    }

    /// Whether Sign In (or Verify) can be pressed.
    var canSubmit: Bool {
        guard !isWorking else { return false }
        return needsMFA ? !mfaCode.isEmpty : (!username.isEmpty && !password.isEmpty && URL(string: serverText) != nil)
    }

    /// What the primary button reads while busy, for VoiceOver (the spinner is silent).
    var busyValue: String {
        isWorking ? (needsMFA ? "Verifying" : "Signing In") : ""
    }

    /// Return in the server field adds no line: the address is one line.
    func stripNewlines() {
        if serverText.contains(where: \.isNewline) { serverText = serverText.filter { !$0.isNewline } }
    }

    /// Starts sign-in (or verification) and returns the task, so a test can wait for it.
    /// - Parameter onSignedIn: Called with fresh tokens on success.
    @discardableResult
    func submit(onSignedIn: @escaping @MainActor (HassServer, AuthTokens) throws -> Void) -> Task<Void, Never>? {
        guard let url = URL(string: serverText.trimmingCharacters(in: .whitespaces)) else { return nil }
        let server = HassServer(baseURL: url)
        isWorking = true
        errorMessage = nil
        return Task { await run(server: server, onSignedIn: onSignedIn) }
    }

    private func run(server: HassServer, onSignedIn: @MainActor (HassServer, AuthTokens) throws -> Void) async {
        defer { isWorking = false }
        do {
            let flow = self.flow ?? makeFlow(server)
            self.flow = flow
            let step = needsMFA
                ? try await flow.submitMFACode(mfaCode)
                : try await flow.signIn(username: username, password: password)
            switch step {
            case .needsMFACode:
                needsMFA = true
            case let .signedIn(tokens):
                password = ""
                try onSignedIn(server, tokens)
            }
        } catch let error as HassLoginFlow.LoginError {
            errorMessage = Self.message(for: error)
            if case .unexpectedResponse = error { reset() }
        } catch {
            errorMessage = error.localizedDescription
            reset()
        }
    }

    private func reset() {
        flow = nil
        needsMFA = false
        mfaCode = ""
    }

    static func message(for error: HassLoginFlow.LoginError) -> String {
        switch error {
        case .invalidCredentials: "Incorrect username or password."
        case .invalidCode: "That code didn't work. Try the current one."
        case let .network(detail): "Couldn't reach the server (\(detail))."
        case let .unexpectedResponse(detail): "Sign-in failed (\(detail)). Try again."
        }
    }

    /// Debug builds only: prefill from launch environment so automated test runs can sign in without
    /// credentials in the repo. Set `FENTON_HASS_USERNAME` / `FENTON_HASS_PASSWORD` in a local,
    /// uncommitted scheme or via `simctl launch` environment.
    func prefillForDebugTesting(_ environment: [String: String] = ProcessInfo.processInfo.environment) {
        #if DEBUG
        if let value = environment["FENTON_HASS_SERVER"] { serverText = value }
        if let value = environment["FENTON_HASS_USERNAME"] { username = value }
        if let value = environment["FENTON_HASS_PASSWORD"] { password = value }
        #endif
    }
}
