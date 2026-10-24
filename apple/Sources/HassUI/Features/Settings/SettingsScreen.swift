import HassCore
import HassDesign
import SwiftUI

// MARK: - List

/// Where the Settings tab pushes besides the household topics. Every push is a value on the tab's path
/// (``SettingsRoute``, ``HouseholdSettingsPage``), so the shell knows when the tab is not at its root.
enum SettingsRoute: Hashable, Sendable {
    case vacation, adminTodo, performance
}

/// The Settings page, the last tab (owner, 2026-10-16: its own page like the web's): the web's household topics
/// (`portedDashboard.ts` `SETTINGS_PAGE_ITEMS`: Vacation, which pushes its own pages, the admin To-Do, hidden from Steph,
/// which pushes too, then the household topics), then Home Assistant Settings, which opens ``HomeAssistantSettingsView``
/// as a full-screen modal (`.agents/design/apple/split-view.md`).
struct SettingsScreen: View {
    @Binding var openTopic: HouseholdSettingsPage?
    @State private var showsHomeAssistant = false
    @State private var feedbackForm: FeedbackKind?
    @AppStorage(ChoresModel.viewerDefaultsKey) private var viewerUserId: String?
    @Environment(\.tileSurface) private var surface
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Creates the list.
    /// - Parameter openTopic: The topic open beside or above the list; constant nil for a static render.
    init(openTopic: Binding<HouseholdSettingsPage?> = .constant(nil)) {
        _openTopic = openTopic
    }

    var body: some View {
        List {
            Group {
                Section {
                    NavigationLink(value: SettingsRoute.vacation) {
                        SettingsLinkRow(
                            title: Vacation.Copy.settingsLinkTitle,
                            subtitle: Vacation.Copy.settingsLinkSubtitle,
                            symbol: SymbolMap.symbol(for: "mdi:airplane"),
                            showsChevron: false
                        )
                    }
                    .accessibilityIdentifier("settings.vacation")
                    if ChoresConfig.showsAdminTodo(to: ChoresConfig.Resident.forUserId(viewerUserId)) {
                        NavigationLink(value: SettingsRoute.adminTodo) {
                            SettingsLinkRow(title: "To-Do", subtitle: "An admin panel for to-do tasks.",
                                            symbol: SymbolMap.symbol(for: "mdi:clipboard-list"), showsChevron: false)
                        }
                        .accessibilityIdentifier("settings.todo")
                    }
                }
                // Appearance sits with the first sections, above the household topics and well before the diagnostic
                // Performance and Feedback sections (owner follow-up, 2026-10-17): Background Blur, then the App
                // Icon row where the system can switch icons.
                AppearanceSettingsSection()
                Section {
                    ForEach(HouseholdSettingsPage.allCases) { page in
                        Button {
                            openTopic = page
                        } label: {
                            SettingsLinkRow(title: page.rowTitle, subtitle: page.subtitle, symbol: page.symbol)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(openTopic == page ? [.isLink, .isSelected] : .isLink)
                        .accessibilityIdentifier("settings.topic.\(page.rawValue)")
                    }
                } header: {
                    SettingsSectionHeader("Household")
                }
                Section {
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
                } footer: {
                    Text("Server, account and Home Assistant's own settings pages.")
                        .foregroundStyle(surface == .page ? HassTokens.Ink.onDarkSecondary : HassTokens.Ink.secondary)
                }
                Section {
                    NavigationLink(value: SettingsRoute.performance) {
                        SettingsLinkRow(title: "Performance", subtitle: "Scrolling, loading and image cache measurements on this device.",
                                        symbol: "gauge.with.dots.needle.67percent", showsChevron: false)
                    }
                    .accessibilityIdentifier("settings.performance")
                }
                FeedbackSettingsSection(openForm: $feedbackForm)
            }
            // On the wallpaper the rows are modules (direction G, Layers); a list in a sheet keeps the system cells.
            .listRowBackground(surface == .page ? HassTokens.Surface.moduleThin(reduceTransparency: reduceTransparency) : nil)
        }
        .accessibilityIdentifier("settings.list")
        .navigationTitle("Settings")
        .homeAssistantSettingsCover(isPresented: $showsHomeAssistant)
        .feedbackFormSheet(item: $feedbackForm)
    }
}

/// One settings topic: icon, title and a wrapping subtitle, like the web's `SettingsLink`
/// (`DashboardViewPage.tsx` `SettingsLink`), with the platform disclosure chevron. Direction G rows (mockup n1
/// settings): a grey glyph, a 17 pt Regular title and a 15 pt secondary subtitle.
struct SettingsLinkRow: View {
    var title: String
    var subtitle: String
    var symbol: String
    /// Off inside a `NavigationLink`, which draws its own chevron.
    var showsChevron = true
    /// An app icon whose small preview replaces the symbol (the App Icon row); nil draws the symbol.
    var appIcon: AppIconChoice?

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: .center, spacing: HassTokens.Spacing.m) {
            // At accessibility sizes the icon sits above the text, so the text keeps the row's width (beside
            // it, the Vacation row grew to 749 pt on the folded iPhone Duo at AX5, 2026-10-11).
            if !typeSize.isAccessibilitySize { icon }
            VStack(alignment: .leading, spacing: 2) {
                if typeSize.isAccessibilitySize { icon }
                Text(title)
                    .font(.body)
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

    @ViewBuilder
    private var icon: some View {
        if let appIcon {
            AppIconPreview(choice: appIcon, side: 30)
                .frame(width: 34)
        } else {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(HassTokens.Ink.secondary)
                .frame(width: 34)
                .accessibilityHidden(true)
        }
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
