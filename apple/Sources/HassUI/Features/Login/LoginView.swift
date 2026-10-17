import HassCore
import HassDesign
import SwiftUI

/// Native username/password sign-in through Home Assistant's login flow, with an MFA step.
struct LoginView: View {
    /// Called with fresh tokens on success.
    var onSignedIn: @MainActor (HassServer, AuthTokens) throws -> Void

    @State private var model: LoginModel
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case server, code, username, password }

    /// Creates the screen.
    /// - Parameters:
    ///   - model: The fields and sign-in flow (tests pass one on a stubbed session).
    ///   - onSignedIn: Called with fresh tokens on success.
    init(model: LoginModel = LoginModel(), onSignedIn: @escaping @MainActor (HassServer, AuthTokens) throws -> Void) {
        _model = State(initialValue: model)
        self.onSignedIn = onSignedIn
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // Wraps rather than truncating long URLs (Dynamic Type audit); Return adds no line.
                    TextField("Server", text: $model.serverText, axis: .vertical)
                        .lineLimit(1...4)
                        .urlEntryField()
                        .onChange(of: model.serverText) { model.stripNewlines() }
                        .focusesFromWholeRow($focusedField, .server)
                        .accessibilityIdentifier("login.server")
                        .disabled(model.needsMFA)
                } header: {
                    FormHeader("Home Assistant")
                }

                if model.needsMFA {
                    Section {
                        TextField("Code", text: $model.mfaCode)
                            .oneTimeCodeEntryField()
                            .focusesFromWholeRow($focusedField, .code)
                            .accessibilityIdentifier("login.code")
                    } header: {
                        FormHeader("Two-factor code")
                    } footer: {
                        FormFooter("Enter the code from your authenticator app.")
                    }
                } else {
                    Section {
                        TextField("Username", text: $model.username)
                            .usernameEntryField()
                            .focusesFromWholeRow($focusedField, .username)
                            .accessibilityIdentifier("login.username")
                        SecureField("Password", text: $model.password)
                            .textContentType(.password)
                            .focusesFromWholeRow($focusedField, .password)
                            .accessibilityIdentifier("login.password")
                    }
                }

                if let errorMessage = model.errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(HassTokens.Ink.danger)
                    }
                }

                Section {
                    // Direction G: the screen's one primary action, a filled capsule.
                    Button { model.submit(onSignedIn: onSignedIn) } label: {
                        HStack(spacing: HassTokens.Spacing.s) {
                            if model.isWorking {
                                ArcSpinner(.inline).accessibilityHidden(true)
                            }
                            Text(model.needsMFA ? "Verify" : "Sign In")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .disabled(!model.canSubmit)
                    // The arc is silent; the button says it is busy.
                    .accessibilityValue(model.busyValue)
                    .accessibilityIdentifier("login.submit")
                }
            }
            .navigationTitle("Sign In")
            .onAppear { model.prefillForDebugTesting() }
        }
        // Direction G is dark throughout; sign-in matches the app it opens.
        .preferredColorScheme(.dark)
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
