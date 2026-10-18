import HassCore
import HassDesign
import SwiftUI

/// The glass module with the username and password rows (owner, 2026-10-17): a label column and a field, 52 pt rows, the
/// system's username and password content types so a password manager offers its credentials, Return moves to the password
/// and then submits.
struct LoginFieldsModule: View {
    @Bindable var model: LoginModel
    var focus: FocusState<LoginField?>.Binding
    var onSubmit: () -> Void

    /// The module's corner radius (`HassTokens.Radius.module`).
    private static let radius = HassTokens.Radius.module

    var body: some View {
        VStack(spacing: 0) {
            usernameRow
            Rectangle()
                .fill(Color.white.opacity(0.14))
                .frame(height: 0.5)
                .padding(.leading, HassTokens.Spacing.l)
                .accessibilityHidden(true)
            passwordRow
        }
        .module(.thin, cornerRadius: Self.radius)
        .overlay {
            RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
                .allowsHitTesting(false)
        }
        // The fields dim while the request is out (owner, 2026-10-17: 50%).
        .opacity(model.isWorking ? 0.5 : 1)
        .disabled(model.isWorking)
        .animation(MotionTokens.quick, value: model.isWorking)
    }

    // MARK: Rows

    @ViewBuilder
    private var usernameRow: some View {
        switch model.mode {
        case .fresh:
            LoginRow(label: "Username") {
                TextField("Username", text: $model.username, prompt: Text(""))
                    .usernameEntryField()
                    .focused(focus, equals: .username)
                    .submitLabel(.next)
                    .onSubmit { focus.wrappedValue = .password }
                    .accessibilityLabel("Username")
                    .accessibilityIdentifier("login.username")
            }
            .contentShape(Rectangle())
            .onTapGesture { focus.wrappedValue = .username }
        case .welcomeBack:
            // The account is known, so it is shown, not asked for.
            LoginRow(label: "Username") {
                Text(model.username)
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Username, \(model.username)")
            .accessibilityIdentifier("login.username.readonly")
        }
    }

    private var passwordRow: some View {
        LoginRow(label: "Password") {
            SecureField("Password", text: $model.password, prompt: Text(""))
                .textContentType(.password)
                .focused(focus, equals: .password)
                .submitLabel(.go)
                .onSubmit(onSubmit)
                .accessibilityLabel("Password")
                .accessibilityIdentifier("login.password")
        }
        .contentShape(Rectangle())
        .onTapGesture { focus.wrappedValue = .password }
        .overlay {
            // A refused password gets a red hairline round its row (the module's bottom corners follow the module).
            if model.failure == .wrongCredentials {
                UnevenRoundedRectangle(bottomLeadingRadius: Self.radius, bottomTrailingRadius: Self.radius, style: .continuous)
                    .strokeBorder(Color(rgb: SignInStyle.error), lineWidth: 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}
