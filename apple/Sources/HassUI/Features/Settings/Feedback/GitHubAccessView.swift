import HassCore
import HassDesign
import SwiftUI

/// The GitHub Access page, pushed inside the feedback sheet: shows who reports are sent as, takes a new
/// fine-grained token (checked before it is saved) and removes the saved one.
///
/// HIG (Entering data): a secure field for secrets, with the requirement explained in visible text;
/// HIG (Action sheets): removing the token is confirmed because sending needs a new one afterwards.
struct GitHubAccessView: View {
    @State private var model: GitHubAccessModel
    @State private var confirmsRemove = false
    @Environment(\.dismiss) private var dismiss
    /// Called after a token is saved or removed.
    private let onChange: () -> Void

    /// Creates the page.
    init(services: FeedbackServices = .current, onChange: @escaping () -> Void = {}) {
        _model = State(initialValue: GitHubAccessModel(services: services))
        self.onChange = onChange
    }

    var body: some View {
        Form {
            if let access = model.access { connectedSection(access) }
            tokenSection
            helpSection
        }
        .navigationTitle("GitHub Access")
        .inlineNavigationTitle()
    }

    // MARK: - Sections

    private func connectedSection(_ access: GitHubAccess) -> some View {
        Section {
            LabeledContent {
                Text("@\(access.login)").foregroundStyle(HassTokens.Ink.secondary)
            } label: {
                Text("Sending as").foregroundStyle(HassTokens.Ink.primary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("feedback.github.login")
            Button("Remove Token", role: .destructive) { confirmsRemove = true }
                .foregroundStyle(HomeAssistantSettingsView.destructiveInk)
                .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget, alignment: .leading)
                .accessibilityIdentifier("feedback.github.remove")
                .confirmationDialog("Remove the GitHub token?", isPresented: $confirmsRemove, titleVisibility: .visible) {
                    Button("Remove Token", role: .destructive) {
                        model.remove()
                        onChange()
                    }
                    .accessibilityIdentifier("feedback.github.remove.confirm")
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Reports can't be sent from your devices until you add a token again.")
                }
        } header: {
            header("Connected")
        }
    }

    private var tokenSection: some View {
        Section {
            SecureField("Paste the token", text: $model.tokenText)
                .textContentType(.password)
                .autocorrectionDisabled()
                .frame(minHeight: HassTokens.minTarget)
                .accessibilityLabel("Access token")
                .accessibilityHint("A fine-grained GitHub token for the \(FeedbackDestination.requests.name) repository.")
                .accessibilityIdentifier("feedback.github.token")
                .onSubmit(save)
            Button(action: save) {
                HStack(spacing: HassTokens.Spacing.s) {
                    Text(model.access == nil ? "Save Token" : "Replace Token")
                    if model.check == .verifying {
                        ArcSpinner(.inline, label: "Checking the token")
                    }
                }
                .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget, alignment: .leading)
                .contentShape(Rectangle())
            }
            .disabled(!model.canSave)
            .accessibilityIdentifier("feedback.github.save")
            if case let .failed(message) = model.check {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(HomeAssistantSettingsView.destructiveInk)
                    .accessibilityIdentifier("feedback.github.error")
            }
        } header: {
            header(model.access == nil ? "Access Token" : "New Token")
        } footer: {
            Text("The token is checked with GitHub, then kept in your iCloud Keychain so your other devices can send reports too. It's never included in a report.")
                .foregroundStyle(HassTokens.Ink.secondary)
        }
    }

    private var helpSection: some View {
        Section {
            Text("On GitHub, create a fine-grained token: choose Only select repositories, pick \(FeedbackDestination.requests.name), and set Issues to Read and write. Then copy it and paste it above.")
                .foregroundStyle(HassTokens.Ink.primary)
                .fixedSize(horizontal: false, vertical: true)
            Link(destination: FeedbackDestination.requests.tokenCreationURL) {
                Label("Create a Token on GitHub", systemImage: "arrow.up.forward.app")
                    .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .accessibilityHint("Opens GitHub in Safari.")
            .accessibilityIdentifier("feedback.github.create")
        } header: {
            header("How to Get One")
        }
    }

    private func header(_ title: String) -> some View {
        Text(title).foregroundStyle(HassTokens.Ink.secondary)
    }

    // MARK: - Actions

    private func save() {
        Task {
            if await model.save() {
                onChange()
                dismiss()
            }
        }
    }
}
