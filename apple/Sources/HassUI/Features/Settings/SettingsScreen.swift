import HassCore
import HassDesign
import SwiftUI

// MARK: - Topics

/// The Settings page's links, in the web's order (`ha-sfenton-react-dash:src/constants/portedDashboard.ts`
/// `SETTINGS_PAGE_ITEMS`; copy from `i18n/locales/en/pageSettings.json`).
enum SettingsTopic: String, CaseIterable, Identifiable, Hashable, Sendable {
    case admin, specialDeviceModes, guests, vacation, todo, machE, homeAssistant

    var id: String { rawValue }

    var title: String {
        switch self {
        case .admin: "Admin Controls"
        case .specialDeviceModes: "Special Device Modes"
        case .guests: "Guest Controls"
        case .vacation: "Vacation"
        case .todo: "To-Do"
        case .machE: "Mach-E"
        case .homeAssistant: "Home Assistant Settings"
        }
    }

    var subtitle: String {
        switch self {
        case .admin: "Presence-Based Toggles, Automation Overrides, and More"
        case .specialDeviceModes: "Allows enabling special device modes, such as High AQI Mode."
        case .guests: "Toggle automations when guests stay over."
        case .vacation: "Set away dates and prepare the house for vacation."
        case .todo: "An admin panel for to-do tasks."
        case .machE: "Controls for the Mustang Mach-E."
        case .homeAssistant: "Access more in-depth Home Assistant details and settings."
        }
    }

    var symbol: String {
        switch self {
        case .admin: SymbolMap.symbol(for: "mdi:shield-account")
        case .specialDeviceModes: SymbolMap.symbol(for: "mdi:tune-vertical")
        case .guests: SymbolMap.symbol(for: "mdi:account-multiple")
        case .vacation: SymbolMap.symbol(for: "mdi:airplane")
        case .todo: SymbolMap.symbol(for: "mdi:clipboard-list")
        case .machE: SymbolMap.symbol(for: "mdi:car-estate")
        case .homeAssistant: SymbolMap.symbol(for: "mdi:cog")
        }
    }
}

// MARK: - Stack

/// The Settings section: the list stays in the leading pane and a topic opens beside it where the window
/// splits (iPad landscape, unfolded Duo landscape), with a placeholder while nothing is selected;
/// elsewhere a topic pushes full screen (`.agents/design/apple/split-view.md` screen classification).
struct SettingsStack: View {
    @Binding var path: NavigationPath
    @SceneStorage("settings.openTopic") private var openTopic: SettingsTopic?

    var body: some View {
        OnDemandSplitStack(path: $path, openItem: $openTopic, alwaysSplit: true) {
            SettingsScreen(openTopic: $openTopic)
        } detail: { topic in
            SettingsTopicScreen(topic: topic)
        } placeholder: {
            ContentUnavailableView("Select a Setting", systemImage: "gearshape", description: Text("Choose a setting from the list."))
                .accessibilityIdentifier("settings.placeholder")
        }
    }
}

// MARK: - List

/// The Settings list: the web's link rows, then the server, connection status and Sign Out.
struct SettingsScreen: View {
    @Binding var openTopic: SettingsTopic?
    @Environment(AppSession.self) private var session
    @Environment(HassConnection.self) private var connection

    var body: some View {
        List {
            Section {
                ForEach(SettingsTopic.allCases) { topic in
                    Button {
                        openTopic = topic
                    } label: {
                        SettingsTopicRow(topic: topic, isSelected: openTopic == topic)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(openTopic == topic ? Color.accentColor.opacity(0.18) : nil)
                    .accessibilityAddTraits(openTopic == topic ? .isSelected : [])
                    .accessibilityIdentifier("settings.topic.\(topic.rawValue)")
                }
            }
            Section("Home Assistant") {
                LabeledContent("Server", value: connection.server.baseURL.host() ?? connection.server.baseURL.absoluteString)
                LabeledContent("Connection", value: statusText)
            }
            Section {
                Button("Sign Out", role: .destructive) { session.signOut() }
                    .accessibilityIdentifier("settings.signOut")
            }
        }
        .navigationTitle("Settings")
    }

    private var statusText: String {
        switch connection.status {
        case .disconnected: "Disconnected"
        case .connecting: "Connecting…"
        case let .connected(version): "Connected (\(version))"
        case .waitingToReconnect: "Reconnecting…"
        case .rejected: "Signed out by server"
        }
    }
}

/// One Settings link: icon, title and subtitle, with a chevron like the web's `SettingsLinkList`.
struct SettingsTopicRow: View {
    var topic: SettingsTopic
    var isSelected: Bool

    var body: some View {
        HStack(spacing: HassTokens.Spacing.m) {
            Image(systemName: topic.symbol)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(topic.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(HassTokens.Ink.primary)
                Text(topic.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(HassTokens.Ink.secondary)
            }
            Spacer(minLength: HassTokens.Spacing.s)
            Image(systemName: "chevron.forward")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(HassTokens.Ink.secondary)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Topic

/// A Settings topic. Each topic's page lands in its own feature lane; until then it says so.
struct SettingsTopicScreen: View {
    var topic: SettingsTopic

    var body: some View {
        ContentUnavailableView(topic.title, systemImage: topic.symbol, description: Text("Coming in a later update."))
            .navigationTitle(topic.title)
            .accessibilityIdentifier("settings.detail.\(topic.rawValue)")
    }
}
