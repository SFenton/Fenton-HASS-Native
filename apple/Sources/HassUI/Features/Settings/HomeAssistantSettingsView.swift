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

    /// Creates the modal; `user` seeds the account rows (hosted tests and previews).
    init(user: HassUser? = nil) {
        _user = State(initialValue: user)
    }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                serverSection
                accountSection
                webSection
                signOutSection
            }
            .modalChrome()
            .navigationTitle("Home Assistant")
            .inlineNavigationTitle()
            .toolbar { SheetCloseItem(identifier: "haSettings.done") { dismiss() } }
            .navigationDestination(for: WebPage.self) { page in
                HomeAssistantWebPage(page: page)
            }
        }
        .task(id: connection.status) { await loadUser() }
    }

    // MARK: - Sections

    private var serverSection: some View {
        Section {
            infoRow("Address", Self.displayedServer(connection.server), id: "haSettings.server")
            infoRow("Connection", Self.statusText(connection.status), id: "haSettings.status")
            if let version = Self.version(connection.status) {
                infoRow("Version", version, id: "haSettings.version")
            }
        } header: {
            sectionHeader("Server")
        }
    }

    private var accountSection: some View {
        Section {
            if let user {
                infoRow("Signed in as", Self.displayedName(user), id: "haSettings.user")
                infoRow("Role", user.roleTitle, id: "haSettings.role")
            } else if userError {
                infoRow("Signed in as", "Unavailable offline", id: "haSettings.user")
            } else {
                LabeledContent("Signed in as") { ArcSpinner(.compact) }
                    .accessibilityIdentifier("haSettings.user")
            }
        } header: {
            sectionHeader("Account")
        }
    }

    private var webSection: some View {
        Section {
            ForEach(Self.webPages(for: user)) { page in
                NavigationLink(value: page) {
                    SettingsLinkRow(title: page.title, subtitle: page.subtitle, symbol: page.symbol, showsChevron: false)
                }
                .accessibilityIdentifier("haSettings.open.\(page.rawValue)")
            }
        } header: {
            sectionHeader("Home Assistant")
        } footer: {
            Text("Opens Home Assistant's own pages, signed in as you.")
                .foregroundStyle(HassTokens.Ink.secondary)
        }
    }

    private var signOutSection: some View {
        Section {
            Button("Sign Out", role: .destructive) { confirmsSignOut = true }
                .foregroundStyle(Self.destructiveInk)
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

    /// A read-only value row. The value uses ``HassTokens/Ink/secondary`` (at least 4.5:1); the
    /// system's secondary value color measured below that on the grouped background.
    private func infoRow(_ title: String, _ value: String, id: String) -> some View {
        LabeledContent {
            Text(value).foregroundStyle(HassTokens.Ink.secondary)
        } label: {
            Text(title).foregroundStyle(HassTokens.Ink.primary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }

    /// A section header in ``HassTokens/Ink/secondary``; the system header gray measured 3.3:1.
    private func sectionHeader(_ title: String) -> some View {
        Text(title).foregroundStyle(HassTokens.Ink.secondary)
    }

    /// The system red at its Increase Contrast value (light and dark), so Sign Out reads at 4.5:1;
    /// the standard red measured below that on the grouped background.
    static var destructiveInk: Color {
        #if canImport(UIKit)
        Color(uiColor: UIColor { traits in
            UIColor.systemRed.resolvedColor(with: traits.modifyingTraits { $0.accessibilityContrast = .high })
        })
        #else
        Color(nsColor: .systemRed)
        #endif
    }

    // MARK: - Actions

    private func loadUser() async {
        (user, userError) = await Self.loadedUser(user, from: connection)
    }

    /// The account rows after a load: the server's user while connected, otherwise the last one
    /// loaded, flagged as failed when there is none and the connection isn't still coming up.
    static func loadedUser(_ current: HassUser?, from connection: HassConnection) async -> (HassUser?, Bool) {
        guard case .connected = connection.status else {
            return (current, current == nil && connection.status != .connecting)
        }
        do {
            return (try await connection.currentUser(), false)
        } catch {
            return (current, current == nil)
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
