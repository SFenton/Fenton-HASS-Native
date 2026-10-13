import HassCore
import HassDesign
import SwiftUI

// MARK: - Stack

/// The Settings section: the list stays in the leading pane and a household page opens beside it where
/// the window splits (iPad landscape, unfolded Duo landscape), with a placeholder while nothing is
/// selected; elsewhere a page pushes full screen (`.agents/design/apple/split-view.md` screen
/// classification).
struct SettingsStack: View {
    @Binding var path: NavigationPath
    @SceneStorage("settings.openTopic") private var openTopic: HouseholdSettingsPage?

    var body: some View {
        OnDemandSplitStack(path: $path, openItem: $openTopic, alwaysSplit: true) {
            SettingsScreen(openTopic: $openTopic)
        } detail: { page in
            HouseholdSettingsDestination(page: page)
        } placeholder: {
            ContentUnavailableView("Select a Setting", systemImage: "gearshape", description: Text("Choose a setting from the list."))
                .accessibilityIdentifier("settings.placeholder")
        }
    }
}

// MARK: - List

/// The Settings list: the web's household topics (`portedDashboard.ts` `SETTINGS_PAGE_ITEMS`: Vacation, which
/// pushes its own pages, the admin To-Do, hidden from Steph, which pushes too, then the household topics), then Home Assistant Settings, which opens ``HomeAssistantSettingsView``
/// as a full-screen modal (`.agents/design/apple/split-view.md`).
struct SettingsScreen: View {
    @Binding var openTopic: HouseholdSettingsPage?
    @State private var showsHomeAssistant = false
    @State private var feedbackForm: FeedbackKind?
    @AppStorage(ChoresModel.viewerDefaultsKey) private var viewerUserId: String?

    /// Creates the list.
    /// - Parameter openTopic: The topic open beside or above the list; constant nil for a static render.
    init(openTopic: Binding<HouseholdSettingsPage?> = .constant(nil)) {
        _openTopic = openTopic
    }

    var body: some View {
        List {
            Section {
                NavigationLink {
                    VacationRoute()
                } label: {
                    SettingsLinkRow(
                        title: Vacation.Copy.settingsLinkTitle,
                        subtitle: Vacation.Copy.settingsLinkSubtitle,
                        symbol: SymbolMap.symbol(for: "mdi:airplane"),
                        showsChevron: false
                    )
                }
                .accessibilityIdentifier("settings.vacation")
                if ChoresConfig.showsAdminTodo(to: ChoresConfig.Resident.forUserId(viewerUserId)) {
                    NavigationLink {
                        AdminTodoScreen()
                    } label: {
                        SettingsLinkRow(title: "To-Do", subtitle: "An admin panel for to-do tasks.",
                                        symbol: SymbolMap.symbol(for: "mdi:clipboard-list"), showsChevron: false)
                    }
                    .accessibilityIdentifier("settings.todo")
                }
                ForEach(HouseholdSettingsPage.allCases) { page in
                    Button {
                        openTopic = page
                    } label: {
                        SettingsLinkRow(title: page.rowTitle, subtitle: page.subtitle, symbol: page.symbol)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(openTopic == page ? Color.accentColor.opacity(0.18) : nil)
                    .accessibilityAddTraits(openTopic == page ? .isSelected : [])
                    .accessibilityIdentifier("settings.topic.\(page.rawValue)")
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
            Section {
                NavigationLink {
                    PerformanceScreen()
                } label: {
                    SettingsLinkRow(title: "Performance", subtitle: "Scrolling, loading and image cache measurements on this device.",
                                    symbol: "gauge.with.dots.needle.67percent", showsChevron: false)
                }
                .accessibilityIdentifier("settings.performance")
            }
            FeedbackSettingsSection(openForm: $feedbackForm)
        }
        .navigationTitle("Settings")
        .homeAssistantSettingsCover(isPresented: $showsHomeAssistant)
        .feedbackFormSheet(item: $feedbackForm)
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

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: HassTokens.Spacing.m) {
            // At accessibility sizes the icon sits above the text, so the text keeps the row's width (beside
            // it, the Vacation row grew to 749 pt on the folded iPhone Duo at AX5, 2026-10-11).
            if !typeSize.isAccessibilitySize { icon }
            VStack(alignment: .leading, spacing: HassTokens.Spacing.xs) {
                if typeSize.isAccessibilitySize { icon }
                Text(title)
                    .font(.headline)
                    .foregroundStyle(HassTokens.Ink.primary)
                    // Wraps instead of truncating in the half-width split pane at large sizes (iPad
                    // landscape audit, 2026-10-11: "Home Assistant Settings" may be clipped).
                    .fixedSize(horizontal: false, vertical: true)
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

    private var icon: some View {
        Image(systemName: symbol)
            .font(.title3)
            .foregroundStyle(.tint)
            .frame(minWidth: 28)
            .accessibilityHidden(true)
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
