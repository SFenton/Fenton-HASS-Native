import HassCore
import HassDesign
import SwiftUI

// MARK: - Section root

extension View {
    /// Adds a section root's leading Open Navigation menu button when the window shows the flyout. Profile and Quick
    /// Links are not here: they are header buttons on every page (``SwiftUI/View/shellHeaderButtons()``).
    func sectionRootChrome() -> some View { modifier(SectionRootChrome()) }
}

/// The section root's shell items (``ShellChrome``).
private struct SectionRootChrome: ViewModifier {
    @Environment(ShellNavigator.self) private var navigator: ShellNavigator?
    @Environment(\.shellChrome) private var chrome
    @AccessibilityFocusState private var buttonFocused: Bool

    func body(content: Content) -> some View {
        content
            .toolbar {
                if chrome.showsMenuButton {
                    ToolbarItem(placement: .navigation) {
                        Button {
                            navigator?.openFlyout()
                        } label: {
                            Label("Open Navigation", systemImage: "line.3.horizontal")
                        }
                        .accessibilityIdentifier("nav.open")
                        .accessibilityFocused($buttonFocused)
                    }
                }
            }
            .onChange(of: navigator?.focusReturnToken) { _, _ in buttonFocused = true }
    }
}

// MARK: - Header buttons

extension View {
    /// Adds the shell's two header buttons to this page: Quick Links, then Profile trailing-most (owner, 2026-10-16:
    /// "Quick Links is a header button next to Profile on every page", tab roots and pushed pages alike, on iPhone, Duo
    /// and iPad). They only ask the ``ShellNavigator`` to present a sheet; the sheets themselves hang on each section's
    /// stack once (``SwiftUI/View/shellSheets(caller:)``), so a pushed page never presents a second copy.
    func shellHeaderButtons() -> some View { modifier(ShellHeaderButtons()) }
}

private struct ShellHeaderButtons: ViewModifier {
    @Environment(ShellNavigator.self) private var navigator: ShellNavigator?
    @Environment(EntityStore.self) private var store: EntityStore?
    @AppStorage(ChoresModel.viewerDefaultsKey) private var viewerUserId: String?

    /// Overdue chores plus expired food (``ProfileSummary/badgeCount(overdue:expiredFood:vacationMode:)``); zero until
    /// the viewer is a known resident, as on the web.
    private var attentionCount: Int {
        guard let store, let viewer = ChoresConfig.Resident.forUserId(viewerUserId) else { return 0 }
        let overdue = ProfileSummary.openCount(store.entity(ProfileSummary.lists(for: viewer).overdue.entityId).state)
        let expired = ProfileSummary.expiredItems(store.entity(ProfileSummary.expiredFoodEntityId).state).count
        let vacation = store.entity(ChoresConfig.vacationModeEntityId).state?.state == "on"
        return ProfileSummary.badgeCount(overdue: overdue, expiredFood: expired, vacationMode: vacation)
    }

    func body(content: Content) -> some View {
        content.toolbar {
            if let navigator {
                HeaderCircleItem { QuickLinksButton { navigator.openQuickLinks() } }
                HeaderCircleItem {
                    ProfileButton(name: navigator.profileName, attentionCount: attentionCount) { navigator.openAccount() }
                }
            }
        }
    }
}

/// One trailing header item drawn as its own glass circle (``SwiftUI/View/headerCircle()``).
///
/// iOS 26 would draw one shared glass capsule behind adjacent bar items and tint a custom view (the monogram's disc
/// measured 2.7:1 under its white initials once the glass lightened it), so the system's background is off and each
/// button draws its own glass: two circles, a fixed 44 pt target, a monogram on its own fill. Earlier systems draw no bar
/// background, so the same circle shows there on a thin material.
private struct HeaderCircleItem<Content: View>: ToolbarContent {
    @ViewBuilder var content: Content

    var body: some ToolbarContent {
        if #available(iOS 26.0, macOS 26.0, *) {
            ToolbarItem(placement: .primaryAction) { content }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .primaryAction) { content }
        }
    }
}

extension View {
    /// A 44 pt navigation-layer circle: Liquid Glass on iOS 26, thin material before (HIG Toolbars, Materials), and a
    /// circular hit area (HIG Buttons: at least 44 pt).
    func headerCircle() -> some View {
        frame(width: HassTokens.minTarget, height: HassTokens.minTarget)
            .navigationGlass(in: Circle())
            .contentShape(Circle())
    }
}

// MARK: - Sheets

extension View {
    /// Presents the Quick Links and Account sheets over this section's stack when the navigator asks for them, once per
    /// section. A page Quick Links chooses pushes on this section's path after the sheet has gone, so the push never
    /// races the dismissal.
    /// - Parameter caller: Service caller for the Security System and room-visit actions.
    func shellSheets(caller: (any HassServiceCalling)?) -> some View { modifier(ShellSheets(caller: caller)) }
}

private struct ShellSheets: ViewModifier {
    var caller: (any HassServiceCalling)?
    @Environment(ShellNavigator.self) private var navigator: ShellNavigator?
    @Environment(\.shellSection) private var section
    @State private var pending: HomeRoute?

    private func binding(_ keyPath: ReferenceWritableKeyPath<ShellNavigator, AppSection?>) -> Binding<Bool> {
        Binding(
            get: { section != nil && navigator?[keyPath: keyPath] == section },
            set: { if !$0, let navigator, navigator[keyPath: keyPath] == section { navigator[keyPath: keyPath] = nil } }
        )
    }

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: binding(\.accountSection)) { AccountSheet().hassSheet(.form, height: .full) }
            .sheet(isPresented: binding(\.quickLinksSection), onDismiss: pushPending) {
                QuickLinksSheet(caller: caller) { pending = $0 }
            }
    }

    private func pushPending() {
        guard let route = pending, let navigator, let section else { return }
        pending = nil
        navigator.paths[section, default: NavigationPath()].append(route)
    }
}

// MARK: - Profile

/// The profile button at the top trailing edge of every page (owner, 2026-10-13: "profile goes in top right"). It shows
/// the signed-in user's initials, or a person symbol until the name is known, and opens the Account sheet
/// (``AccountSheet``: the web's profile modal, Your Summary, with the account and Sign Out).
struct ProfileButton: View {
    /// The signed-in user's display name, when known.
    var name: String?
    /// Overdue chores plus expired food, badged on the avatar ("9+" past nine) and spoken with its value.
    var attentionCount = 0
    var action: () -> Void

    /// The monogram's fill (the light-mode action blue, 5.6:1 under white).
    static let fill = Color(red: 0.0, green: 0.40, blue: 0.80)

    /// Up to two initials from a display name ("Stephen Fenton" → "SF"); nil when it has no letters.
    static func initials(_ name: String?) -> String? {
        guard let name else { return nil }
        let letters = name.split(whereSeparator: \.isWhitespace).prefix(2).compactMap(\.first).map(String.init)
        let value = letters.joined().uppercased()
        return value.isEmpty ? nil : value
    }

    /// "Stephen Fenton, 3 items need attention": the person, then what is waiting (web `profile.openWithAttention`).
    static func accessibilityValue(name: String?, attentionCount: Int) -> String {
        let attention = attentionCount > 0 ? "\(attentionCount) \(attentionCount == 1 ? "item needs" : "items need") attention" : nil
        return [name, attention].compactMap { $0 }.joined(separator: ", ")
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                // The glass is its own layer under the monogram: inside the glass effect the disc was lightened until its
                // white initials measured 2.7:1.
                Color.clear.headerCircle()
                if let initials = Self.initials(name) {
                    Text(initials)
                        .font(.footnote.weight(.semibold))
                        // A bar item keeps its size; the Large Content Viewer shows it bigger (HIG Toolbars,
                        // Accessibility), so the initials stop growing past the disc.
                        .dynamicTypeSize(...DynamicTypeSize.xLarge)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .frame(width: 32, height: 32)
                        // Fixed deep blue: white text stays above 5:1 in light and dark mode.
                        .background(ProfileButton.fill, in: Circle())
                } else {
                    Image(systemName: "person.crop.circle")
                        .font(.title3)
                        .foregroundStyle(.primary)
                }
            }
            .frame(width: HassTokens.minTarget, height: HassTokens.minTarget)
        }
        .overlay(alignment: .topTrailing) {
            if let text = ProfileSummary.badgeText(attentionCount) {
                Text(text)
                    .font(.caption2.weight(.bold))
                    .dynamicTypeSize(...DynamicTypeSize.xLarge)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .frame(minWidth: 16, minHeight: 16)
                    .background(HassTokens.Ink.badge, in: Capsule())
                    .offset(x: 4, y: -2)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityShowsLargeContentViewer {
            Label("Profile", systemImage: "person.crop.circle")
        }
        .accessibilityLabel("Profile")
        .accessibilityValue(Self.accessibilityValue(name: name, attentionCount: attentionCount))
        .accessibilityHint("Opens your summary and account")
        .accessibilityIdentifier("nav.profile")
    }
}
