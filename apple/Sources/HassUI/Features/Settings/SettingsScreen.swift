import HassCore
import HassDesign
import SwiftUI

// MARK: - Topics

/// The Settings topics that open in place, in the web's order (`ha-sfenton-react-dash:src/constants/portedDashboard.ts`
/// `SETTINGS_PAGE_ITEMS`; copy from `i18n/locales/en/pageSettings.json`). The web's last item, Home Assistant
/// Settings, is not a topic: it opens ``HomeAssistantSettingsView`` full screen.
enum SettingsTopic: String, CaseIterable, Identifiable, Hashable, Sendable {
    case admin, specialDeviceModes, guests, vacation, todo, machE

    var id: String { rawValue }

    var title: String {
        switch self {
        case .admin: "Admin Controls"
        case .specialDeviceModes: "Special Device Modes"
        case .guests: "Guest Controls"
        case .vacation: "Vacation"
        case .todo: "To-Do"
        case .machE: "Mach-E"
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

/// The Settings list: the web's topics, then Home Assistant Settings, which opens full screen.
struct SettingsScreen: View {
    @Binding var openTopic: SettingsTopic?
    @State private var showsHomeAssistant = false

    /// Creates the list.
    /// - Parameter openTopic: The topic open beside or above the list; constant nil for a static render.
    init(openTopic: Binding<SettingsTopic?> = .constant(nil)) {
        _openTopic = openTopic
    }

    var body: some View {
        List {
            Section {
                ForEach(SettingsTopic.allCases) { topic in
                    Button {
                        openTopic = topic
                    } label: {
                        SettingsLinkRow(title: topic.title, subtitle: topic.subtitle, symbol: topic.symbol)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(openTopic == topic ? Color.accentColor.opacity(0.18) : nil)
                    .accessibilityAddTraits(openTopic == topic ? .isSelected : [])
                    .accessibilityIdentifier("settings.topic.\(topic.rawValue)")
                }
                Button { showsHomeAssistant = true } label: {
                    SettingsLinkRow(
                        title: HomeAssistantSettingsView.linkTitle,
                        subtitle: HomeAssistantSettingsView.linkSubtitle,
                        symbol: SymbolMap.symbol(for: "mdi:cog")
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.homeAssistant")
                .accessibilityHint("Opens server, account and sign-out options.")
            }
        }
        .navigationTitle("Settings")
        .homeAssistantSettingsCover(isPresented: $showsHomeAssistant)
    }
}

/// One settings topic: icon, bold title and a wrapping subtitle, like the web's `SettingsLink`
/// (`DashboardViewPage.tsx` `SettingsLink`), with the platform disclosure chevron.
struct SettingsLinkRow: View {
    var title: String
    var subtitle: String
    var symbol: String
    /// Off inside a `NavigationLink`, which draws its own chevron.
    var showsChevron = true

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: HassTokens.Spacing.m) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(minWidth: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: HassTokens.Spacing.xs) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(HassTokens.Ink.primary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(HassTokens.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if showsChevron {
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, HassTokens.Spacing.xs)
        .frame(minHeight: HassTokens.minTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// Presents Home Assistant settings full screen on iOS (a sheet on macOS, where hosted tests run).
    func homeAssistantSettingsCover(isPresented: Binding<Bool>) -> some View {
        #if os(iOS)
        fullScreenCover(isPresented: isPresented) { HomeAssistantSettingsView() }
        #else
        sheet(isPresented: isPresented) { HomeAssistantSettingsView() }
        #endif
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
