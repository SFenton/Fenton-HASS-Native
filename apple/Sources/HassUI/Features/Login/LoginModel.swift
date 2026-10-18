import Foundation
import HassCore
import HassTelemetry
import Observation

/// What the sign-in screen holds and does: the two fields, the in-flight state, what went wrong, and the Home Assistant login
/// flow behind Sign In (kept apart from ``LoginView`` so the flow is tested without a window).
///
/// The server is fixed (`HassServer.fentonHome`; owner, 2026-10-17): there is no address field, and no second step. An account
/// with two-step sign-in turned on is told to turn it off rather than shown a code field nobody has used.
@MainActor
@Observable
final class LoginModel {
    /// Which sign-in this is.
    enum Mode: Equatable {
        /// A new sign-in: username and password.
        case fresh
        /// The session ended: the account is known, so only the password is asked for.
        case welcomeBack(RememberedAccount)
    }

    /// What went wrong, in the words the screen uses.
    enum Failure: Equatable {
        /// Home Assistant said no to the username or password.
        case wrongCredentials
        /// The server could not be reached (offline, restarting, a gateway error). `detail` is the raw reason.
        case unreachable(detail: String)
        /// Anything else. `detail` is the raw reason.
        case failed(detail: String)
        /// The account asks for a second step, which the app does not do.
        case twoStepUnsupported

        /// The red line under the fields, for the failures that sit beside them rather than in a card.
        var inlineMessage: String? {
            switch self {
            case .wrongCredentials: LoginCopy.wrongCredentials
            case .twoStepUnsupported: LoginCopy.twoStepUnsupported
            case .unreachable, .failed: nil
            }
        }

        /// The card's title, for the failures that get one.
        var cardTitle: String? {
            switch self {
            case .unreachable: LoginCopy.unreachableTitle
            case .failed: LoginCopy.failedTitle
            case .wrongCredentials, .twoStepUnsupported: nil
            }
        }

        /// The card's plain-words body.
        var cardBody: String? {
            switch self {
            case .unreachable: LoginCopy.unreachableBody
            case .failed: LoginCopy.failedBody
            case .wrongCredentials, .twoStepUnsupported: nil
            }
        }

        /// The raw reason behind a card, for its Details.
        var detail: String? {
            switch self {
            case let .unreachable(detail), let .failed(detail): detail.isEmpty ? nil : detail
            case .wrongCredentials, .twoStepUnsupported: nil
            }
        }

        /// What VoiceOver announces when the failure appears.
        var announcement: String {
            inlineMessage ?? [cardTitle, cardBody].compactMap { $0 }.joined(separator: ". ")
        }
    }

    /// Which sign-in this is; changes to ``Mode/fresh`` when the person picks a different account.
    private(set) var mode: Mode
    /// The Home Assistant server: always the household's (debug builds may point it elsewhere for journeys).
    private(set) var server: HassServer = .fentonHome
    /// The account name.
    var username: String
    /// The password. Cleared once sign-in succeeds or is refused; never stored.
    var password = ""
    /// Whether a request is in flight.
    private(set) var isWorking = false
    /// What went wrong, for the screen to show.
    private(set) var failure: Failure?
    /// Bumped when the password field should take focus (after a refusal).
    private(set) var passwordFocusToken = 0

    @ObservationIgnored private let makeFlow: (HassServer) -> HassLoginFlow
    @ObservationIgnored private let store: RememberedAccountStore

    /// Creates the model.
    /// - Parameters:
    ///   - mode: A fresh sign-in, or a welcome back for an account whose session ended.
    ///   - store: Where the last username is kept; a fresh sign-in starts with it filled in.
    ///   - makeFlow: Builds the login flow for the server; tests pass one on a stubbed session.
    init(mode: Mode = .fresh, store: RememberedAccountStore = RememberedAccountStore(),
         makeFlow: @escaping (HassServer) -> HassLoginFlow = LoginModel.defaultFlow) {
        self.mode = mode
        self.store = store
        self.makeFlow = makeFlow
        switch mode {
        case let .welcomeBack(account): username = account.username
        case .fresh: username = store.username ?? ""
        }
    }

    /// The flow for the real server; debug builds can ask for a canned one (`FENTON_SIGNIN_STUB`, see ``DebugSignInStub``).
    nonisolated static func defaultFlow(_ server: HassServer) -> HassLoginFlow {
        #if DEBUG
        if let session = DebugSignInStub.session() { return HassLoginFlow(server: server, session: session) }
        #endif
        return HassLoginFlow(server: server)
    }

    // MARK: Reading

    /// Whether Sign In can be pressed.
    var canSubmit: Bool {
        !isWorking && !username.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
    }

    /// The primary button's words: Sign In, Signing In… while a request is out, Try Again after the server could not be
    /// reached or the sign-in failed (the fields keep their values).
    var buttonTitle: String {
        if isWorking { return LoginCopy.busyTitle }
        switch failure {
        case .unreachable, .failed: return LoginCopy.retryTitle
        case .wrongCredentials, .twoStepUnsupported, nil: return LoginCopy.signInTitle
        }
    }

    /// What the primary button says is happening, for VoiceOver (the spinner is silent).
    var busyValue: String { isWorking ? "Signing In" : "" }

    // MARK: Actions

    /// Starts sign-in and returns the task, so a test can wait for it.
    /// - Parameter onSignedIn: Called with fresh tokens on success.
    @discardableResult
    func submit(onSignedIn: @escaping @MainActor (HassServer, AuthTokens) throws -> Void) -> Task<Void, Never>? {
        guard canSubmit else { return nil }
        isWorking = true
        failure = nil
        Telemetry.beginTracked(Telemetry.Name.signIn)
        return Task { await run(onSignedIn: onSignedIn) }
    }

    /// Drops the remembered account and asks for a username as well (Use a Different Account).
    func useDifferentAccount() {
        store.forget()
        mode = .fresh
        username = ""
        password = ""
        failure = nil
    }

    private func run(onSignedIn: @MainActor (HassServer, AuthTokens) throws -> Void) async {
        defer { isWorking = false }
        let name = username.trimmingCharacters(in: .whitespaces)
        do {
            switch try await makeFlow(server).signIn(username: name, password: password) {
            case .needsMFACode:
                Telemetry.cancelTracked(Telemetry.Name.signIn)
                failure = .twoStepUnsupported
            case let .signedIn(tokens):
                Telemetry.endTracked(Telemetry.Name.signIn)
                password = ""
                store.remember(username: name)
                // Home has until the end of the arrival animation (RootView ends it).
                Telemetry.beginTracked(Telemetry.Name.arrival)
                do {
                    try onSignedIn(server, tokens)
                } catch {
                    Telemetry.cancelTracked(Telemetry.Name.arrival)
                    failure = .failed(detail: error.localizedDescription)
                }
            }
        } catch {
            Telemetry.cancelTracked(Telemetry.Name.signIn)
            failure = Self.failure(for: error)
            if failure == .wrongCredentials {
                // A wrong password is retyped from nothing; the username stays.
                password = ""
                passwordFocusToken += 1
            }
        }
    }

    /// How an error from the login flow reads on the screen.
    static func failure(for error: any Error) -> Failure {
        guard let error = error as? HassLoginFlow.LoginError else { return .failed(detail: error.localizedDescription) }
        switch error {
        case .invalidCredentials: return .wrongCredentials
        case let .network(detail): return .unreachable(detail: detail)
        case let .unexpectedResponse(detail): return .failed(detail: detail)
        case .invalidCode: return .failed(detail: "invalid code")
        }
    }

    /// Debug builds only: prefill from launch environment so automated test runs can sign in without
    /// credentials in the repo. Set `FENTON_HASS_USERNAME` / `FENTON_HASS_PASSWORD` in a local,
    /// uncommitted scheme or via `simctl launch` environment. `FENTON_HASS_SERVER` points a journey at another server.
    func prefillForDebugTesting(_ environment: [String: String] = ProcessInfo.processInfo.environment) {
        #if DEBUG
        if let value = environment["FENTON_HASS_SERVER"], let url = URL(string: value) { server = HassServer(baseURL: url) }
        if let value = environment["FENTON_HASS_USERNAME"] { username = value }
        if let value = environment["FENTON_HASS_PASSWORD"] { password = value }
        #endif
    }
}
