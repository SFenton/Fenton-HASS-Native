import HassCore
import SwiftUI

/// Native username/password sign-in through Home Assistant's login flow, with an MFA step.
struct LoginView: View {
    /// Called with fresh tokens on success.
    var onSignedIn: @MainActor (HassServer, AuthTokens) throws -> Void

    @State private var serverText = HassServer.fentonHome.baseURL.absoluteString
    @State private var username = ""
    @State private var password = ""
    @State private var mfaCode = ""
    @State private var flow: HassLoginFlow?
    @State private var needsMFA = false
    @State private var isWorking = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case server, code, username, password }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // Wraps rather than truncating long URLs (Dynamic Type audit); Return adds no line.
                    TextField("Server", text: $serverText, axis: .vertical)
                        .lineLimit(1...4)
                        .urlEntryField()
                        .onChange(of: serverText) { _, value in
                            if value.contains(where: \.isNewline) { serverText = value.filter { !$0.isNewline } }
                        }
                        .focusesFromWholeRow($focusedField, .server)
                        .accessibilityIdentifier("login.server")
                        .disabled(needsMFA)
                } header: {
                    Text("Home Assistant")
                }

                if needsMFA {
                    Section {
                        TextField("Code", text: $mfaCode)
                            .oneTimeCodeEntryField()
                            .focusesFromWholeRow($focusedField, .code)
                            .accessibilityIdentifier("login.code")
                    } header: {
                        Text("Two-factor code")
                    } footer: {
                        Text("Enter the code from your authenticator app.")
                    }
                } else {
                    Section {
                        TextField("Username", text: $username)
                            .usernameEntryField()
                            .focusesFromWholeRow($focusedField, .username)
                            .accessibilityIdentifier("login.username")
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .focusesFromWholeRow($focusedField, .password)
                            .accessibilityIdentifier("login.password")
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button(action: submit) {
                        HStack {
                            Text(needsMFA ? "Verify" : "Sign In")
                            if isWorking {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(!canSubmit)
                    .accessibilityIdentifier("login.submit")
                }
            }
            .navigationTitle("Sign In")
            .onAppear(perform: prefillForDebugTesting)
        }
    }

    private var canSubmit: Bool {
        guard !isWorking else { return false }
        return needsMFA ? !mfaCode.isEmpty : (!username.isEmpty && !password.isEmpty && URL(string: serverText) != nil)
    }

    private func submit() {
        guard let url = URL(string: serverText.trimmingCharacters(in: .whitespaces)) else { return }
        let server = HassServer(baseURL: url)
        isWorking = true
        errorMessage = nil
        Task {
            defer { isWorking = false }
            do {
                let flow = self.flow ?? HassLoginFlow(server: server)
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
                errorMessage = message(for: error)
                if case .unexpectedResponse = error { reset() }
            } catch {
                errorMessage = error.localizedDescription
                reset()
            }
        }
    }

    private func reset() {
        flow = nil
        needsMFA = false
        mfaCode = ""
    }

    private func message(for error: HassLoginFlow.LoginError) -> String {
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
    private func prefillForDebugTesting() {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if let value = environment["FENTON_HASS_SERVER"] { serverText = value }
        if let value = environment["FENTON_HASS_USERNAME"] { username = value }
        if let value = environment["FENTON_HASS_PASSWORD"] { password = value }
        #endif
    }
}

private extension View {
    /// Fills the Form row (44 pt minimum) and focuses the field from a tap anywhere in it, not only on
    /// its text.
    func focusesFromWholeRow<Value: Hashable>(_ focus: FocusState<Value?>.Binding, _ value: Value) -> some View {
        frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { focus.wrappedValue = value }
            .focused(focus, equals: value)
    }
}
