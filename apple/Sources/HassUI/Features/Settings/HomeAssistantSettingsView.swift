import HassCore
import HassDesign
import SwiftUI

/// Home Assistant settings: the server and its connection, the signed-in account, Home Assistant's own
/// Settings and Profile pages (signed-in web view), and Sign Out.
///
/// The web dashboard runs inside Home Assistant, so its "Home Assistant Settings" row just links to
/// `/config` (`portedDashboard.ts` `SETTINGS_PAGE_ITEMS`). The app owns its sign-in, so the server,
/// account and sign-out live here natively, with the backend pages one tap further.
struct HomeAssistantSettingsView: View {
    /// Row title in Settings (`pages/settings.json` `items.homeAssistant.title`).
    static let linkTitle = "Home Assistant Settings"
    /// Row subtitle in Settings (`pages/settings.json` `items.homeAssistant.subtitle`).
    static let linkSubtitle = "Access more in-depth Home Assistant details and settings."

    /// A Home Assistant web page the modal can open.
    enum WebPage: String, Hashable, Identifiable, CaseIterable {
        case settings, profile

        var id: String { rawValue }
        var path: String { self == .settings ? "/config" : "/profile" }
        var title: String { self == .settings ? "Settings" : "Profile" }
        var symbol: String { self == .settings ? "gearshape" : "person.crop.circle" }
        var subtitle: String {
            self == .settings
                ? "Devices, integrations, automations and system."
                : "Language, theme and security for this account."
        }
    }

    @Environment(AppSession.self) private var session
    @Environment(HassConnection.self) private var connection
    @Environment(\.dismiss) private var dismiss
    @State private var user: HassUser?
    @State private var userError = false
    @State private var confirmsSignOut = false
    @State private var path: [WebPage] = []

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                serverSection
                accountSection
                webSection
                signOutSection
            }
            .navigationTitle("Home Assistant")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("haSettings.done")
                }
            }
            .navigationDestination(for: WebPage.self) { page in
                HomeAssistantWebPage(page: page)
            }
        }
        .task(id: connection.status) { await loadUser() }
    }

    // MARK: - Sections

    private var serverSection: some View {
        Section("Server") {
            LabeledContent("Address", value: Self.displayedServer(connection.server))
                .accessibilityIdentifier("haSettings.server")
            LabeledContent("Connection", value: Self.statusText(connection.status))
                .accessibilityIdentifier("haSettings.status")
            if let version = Self.version(connection.status) {
                LabeledContent("Version", value: version)
                    .accessibilityIdentifier("haSettings.version")
            }
        }
    }

    private var accountSection: some View {
        Section("Account") {
            if let user {
                LabeledContent("Signed in as", value: Self.displayedName(user))
                    .accessibilityIdentifier("haSettings.user")
                LabeledContent("Role", value: user.roleTitle)
                    .accessibilityIdentifier("haSettings.role")
            } else if userError {
                LabeledContent("Signed in as", value: "Unavailable offline")
                    .accessibilityIdentifier("haSettings.user")
            } else {
                LabeledContent("Signed in as") { ProgressView().accessibilityLabel("Loading") }
                    .accessibilityIdentifier("haSettings.user")
            }
        }
    }

    private var webSection: some View {
        Section {
            ForEach(Self.webPages(for: user)) { page in
                NavigationLink(value: page) {
                    SettingsLinkLabel(title: page.title, subtitle: page.subtitle, symbol: page.symbol)
                }
                .accessibilityIdentifier("haSettings.open.\(page.rawValue)")
            }
        } header: {
            Text("Home Assistant")
        } footer: {
            Text("Opens Home Assistant's own pages, signed in as you.")
        }
    }

    private var signOutSection: some View {
        Section {
            Button("Sign Out", role: .destructive) { confirmsSignOut = true }
                .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget)
                .accessibilityIdentifier("haSettings.signOut")
                .confirmationDialog(
                    "Sign out of Home Assistant?",
                    isPresented: $confirmsSignOut,
                    titleVisibility: .visible
                ) {
                    Button("Sign Out", role: .destructive) { signOut() }
                        .accessibilityIdentifier("haSettings.signOut.confirm")
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("You'll need your username and password to sign in again.")
                }
        }
    }

    // MARK: - Actions

    private func loadUser() async {
        guard case .connected = connection.status else {
            if user == nil { userError = connection.status != .connecting }
            return
        }
        do {
            user = try await connection.currentUser()
            userError = false
        } catch {
            if user == nil { userError = true }
        }
    }

    private func signOut() {
        dismiss()
        session.signOut()
    }

    // MARK: - Formatting (unit-tested)

    /// The server's host (with a non-default port), hidden in redacted screenshots.
    static func displayedServer(_ server: HassServer, redacting: Bool = ScreenshotPrivacy.isRedacting) -> String {
        if redacting { return "Hidden for screenshot" }
        let url = server.baseURL
        guard let host = url.host() else { return url.absoluteString }
        if let port = url.port { return "\(host):\(port)" }
        return host
    }

    /// The user's name, hidden in redacted screenshots.
    static func displayedName(_ user: HassUser, redacting: Bool = ScreenshotPrivacy.isRedacting) -> String {
        if redacting { return "Hidden for screenshot" }
        return user.name.flatMap { $0.isEmpty ? nil : $0 } ?? "Unnamed user"
    }

    /// Connection status in words.
    static func statusText(_ status: HassConnection.Status) -> String {
        switch status {
        case .disconnected: "Disconnected"
        case .connecting: "Connecting…"
        case .connected: "Connected"
        case .waitingToReconnect: "Reconnecting…"
        case .rejected: "Signed out by server"
        }
    }

    /// Home Assistant's version while connected.
    static func version(_ status: HassConnection.Status) -> String? {
        if case let .connected(version) = status, !version.isEmpty { return version }
        return nil
    }

    /// Settings needs an administrator; Profile is always available. Unknown users see both, and
    /// Home Assistant itself refuses Settings if the role turns out to be wrong.
    static func webPages(for user: HassUser?) -> [WebPage] {
        guard let user, !user.isAdmin, !user.isOwner else { return WebPage.allCases }
        return [.profile]
    }
}

/// ``SettingsLinkRow`` without its own chevron, for `NavigationLink`s that draw one.
struct SettingsLinkLabel: View {
    var title: String
    var subtitle: String
    var symbol: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: HassTokens.Spacing.m) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(minWidth: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: HassTokens.Spacing.xs) {
                Text(title).font(.headline).foregroundStyle(HassTokens.Ink.primary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(HassTokens.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, HassTokens.Spacing.xs)
        .frame(minHeight: HassTokens.minTarget)
        .accessibilityElement(children: .combine)
    }
}
