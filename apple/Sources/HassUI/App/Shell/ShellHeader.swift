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

    /// The menu button is the leading-most bar item: `.navigation` would be pushed trailing by an inline-large title.
    private static var menuPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarLeading
        #else
        .navigation
        #endif
    }

    func body(content: Content) -> some View {
        content
            .toolbar {
                if chrome.showsMenuButton {
                    ToolbarItem(placement: Self.menuPlacement) {
                        Button {
                            navigator?.openFlyout()
                        } label: {
                            Label("Open Navigation", systemImage: "line.3.horizontal")
                        }
                        .accessibilityHint("Opens the navigation menu")
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
    @Environment(HassConnection.self) private var connection: HassConnection?
    @Environment(ReconnectingIndicator.self) private var reconnecting: ReconnectingIndicator?
    @AppStorage(ChoresModel.viewerDefaultsKey) private var viewerUserId: String?

    /// Overdue chores plus expired food (``ProfileSummary/badgeCount(overdue:expiredFood:vacationMode:)``); zero until
    /// the viewer is a known resident, as on the web.
    private var attentionCount: Int {
        ShellAttention.count(store: store, viewerUserId: viewerUserId)
    }

    func body(content: Content) -> some View {
        content.toolbar {
            if let navigator {
                ShellHeaderItems(
                    profileName: navigator.profileName,
                    attentionCount: attentionCount,
                    isOffline: connection?.isOffline ?? false,
                    reconnecting: reconnecting?.isPresent == true ? reconnecting : nil,
                    openQuickLinks: { navigator.openQuickLinks() },
                    openAccount: { navigator.openAccount() }
                )
            }
        }
    }
}

/// The shell's trailing header items, Quick Links then Profile (owner, 2026-10-18, option A: FestivalNativeApps
/// parity, HIG Toolbars "Item groupings"), with the reconnecting arc before them while the connection is retrying
/// (``ReconnectingArc``; owner, 2026-10-23): the same 12 pt from Quick Links as Quick Links is from Profile, so the trailing group
/// grows to its left and the two circles never move.
///
/// On iOS 26 the bar draws Quick Links' glass circle itself and a `ToolbarSpacer(.fixed)` separates it from Profile, the way
/// FestivalNativeApps separates its page tools from its account group: the two stay separate circles and the bar never
/// merges them into one capsule. Profile with a known name is its own filled 44 pt disc with the bar's shared glass hidden,
/// overhanging the hidden-glass padding so the disc fills exactly the circle the glass would have drawn
/// (``ProfileButton/Metrics``); without a name it is the person symbol on the bar's standard glass circle
/// (``ProfileButton/Presentation``). Measured on the iPhone 17 Pro simulator (iOS 27): Quick Links' glass 44 pt, the disc
/// 44 pt, 12 pt between them. In the Duo's vertical bar (owner, 2026-10-20) both share one glass group and no spacer is added (``EnvironmentValues/shellInVerticalBar``), and before
/// iOS 26 the bar draws no glass, so each button draws its own material circle and no spacer is added.
struct ShellHeaderItems: ToolbarContent {
    var profileName: String?
    var attentionCount = 0
    var isOffline = false
    /// The indicator, passed only while the arc is in the bar.
    var reconnecting: ReconnectingIndicator?
    var openQuickLinks: () -> Void
    var openAccount: () -> Void
    @Environment(\.shellInVerticalBar) private var inVerticalBar

    var body: some ToolbarContent {
        if #available(iOS 26.0, macOS 26.0, *), ShellHeaderGrouping.resolve(inVerticalBar: inVerticalBar) == .oneGroup {
            // Owner, 2026-10-20: on the Duo's vertical rail the two buttons share one glass blob. One item group is one
            // glass shape; the person symbol (a monogram custom view stays in the horizontal bar, measured) shares the glass, and no spacer is added (HIG Designing for iPhone Duo).
            // The arc is a custom view, so like the monogram it stays in the horizontal page header, trailing, and never joins the
            // rail (owner, 2026-10-23: "spinner would still appear in page header on right side"). Nothing sits beside it, so
            // it keeps its own padding (`besideQuickLinks: false`).
            if let reconnecting { ReconnectingArcItem(indicator: reconnecting, besideQuickLinks: false) }
            ToolbarItemGroup(placement: .primaryAction) {
                QuickLinksButton(action: openQuickLinks)
                ProfileButton(name: profileName, attentionCount: attentionCount, isOffline: isOffline, grouped: true, action: openAccount)
            }
        } else if #available(iOS 26.0, macOS 26.0, *) {
            if let reconnecting {
                ReconnectingArcItem(indicator: reconnecting)
                ToolbarSpacer(.fixed, placement: .primaryAction)
            }
            ToolbarItem(placement: .primaryAction) { QuickLinksButton(action: openQuickLinks) }
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ProfileHeaderItem(name: profileName, attentionCount: attentionCount, isOffline: isOffline, action: openAccount)
        } else {
            if let reconnecting { ReconnectingArcItem(indicator: reconnecting) }
            ToolbarItem(placement: .primaryAction) { QuickLinksButton(action: openQuickLinks) }
            ProfileHeaderItem(name: profileName, attentionCount: attentionCount, isOffline: isOffline, action: openAccount)
        }
    }
}

/// The reconnecting arc's bar item: on iOS 26 its shared glass is hidden, so the arc floats on the wallpaper instead of sitting
/// in a glass circle (it is a status, not a button).
private struct ReconnectingArcItem: ToolbarContent {
    var indicator: ReconnectingIndicator
    /// Quick Links follows the arc in the same bar (false on the Duo's rail, where it sits in the page header alone).
    var besideQuickLinks = true

    var body: some ToolbarContent {
        if #available(iOS 26.0, macOS 26.0, *) {
            ToolbarItem(placement: .primaryAction) { ReconnectingArc(indicator: indicator, besideQuickLinks: besideQuickLinks) }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .primaryAction) { ReconnectingArc(indicator: indicator, besideQuickLinks: besideQuickLinks) }
        }
    }
}

/// The Profile bar item: hides the bar's shared glass while the monogram is its own disc (iOS 26), and keeps the
/// system glass behind the person symbol.
private struct ProfileHeaderItem: ToolbarContent {
    var name: String?
    var attentionCount: Int
    var isOffline = false
    var action: () -> Void

    var body: some ToolbarContent {
        if #available(iOS 26.0, macOS 26.0, *) {
            ToolbarItem(placement: .primaryAction) {
                ProfileButton(name: name, attentionCount: attentionCount, isOffline: isOffline, action: action)
            }
            .sharedBackgroundVisibility(ProfileButton.Presentation.resolve(name: name).sharedBackground)
        } else {
            ToolbarItem(placement: .primaryAction) {
                ProfileButton(name: name, attentionCount: attentionCount, isOffline: isOffline, action: action)
            }
        }
    }
}

extension View {
    /// A 44 pt navigation-layer circle for a bar item that has no glass of its own: thin material before iOS 26 (HIG Toolbars,
    /// Materials), with a circular hit area (HIG Buttons: at least 44 pt). On iOS 26 the bar draws each item's glass circle,
    /// so the header buttons only use this before then.
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
            .sheet(isPresented: binding(\.accountSection)) { YourSummarySheet().hassSheet(.form, height: .full) }
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
/// the signed-in user's initials on a 44 pt disc that is the whole button, or a person symbol until the name is known,
/// and opens the Account sheet (``YourSummarySheet``: the web's profile modal, Your Summary, with the account and Sign Out on
/// its Profile tab).
///
/// Owner 2026-10-18, option A: the avatar takes its whole container, the way FestivalNativeApps' `RootProfileButton` does
/// (FST issue #311); Quick Links stays a separate glass circle beside it (``ShellHeaderItems``).
struct ProfileButton: View {
    /// The signed-in user's display name, when known.
    var name: String?
    /// Overdue chores plus expired food, badged on the avatar ("9+" past nine) and spoken with its value.
    var attentionCount = 0
    /// No network path: a small `icloud.slash` badge sits on the bottom-right of the disc, opposite the attention badge.
    /// Chosen over a mark beside Quick Links because the header's trailing group is already two fixed 44 pt circles
    /// (a third item would crowd the Duo's vertical rail and the iPad bar) and the badge rides on the Profile circle in
    /// every bar without changing the layout.
    var isOffline = false
    /// The button sits in the Duo's shared glass group in the vertical rail. A monogram (a custom view) does not move into
    /// the rail (measured: it stayed 68 pt off the rail's column), so the group shows the person symbol instead.
    var grouped = false
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
    static func accessibilityValue(name: String?, attentionCount: Int, isOffline: Bool = false) -> String {
        let attention = attentionCount > 0 ? "\(attentionCount) \(attentionCount == 1 ? "item needs" : "items need") attention" : nil
        return [name, attention, isOffline ? "Offline" : nil].compactMap { $0 }.joined(separator: ", ")
    }

    // MARK: Presentation

    /// How the button draws for a name (FestivalNativeApps `RootProfileButton.Presentation`).
    enum Presentation: Equatable {
        /// The initials on the button's own filled disc.
        case monogram(String)
        /// The person symbol on the bar's standard glass circle, until the name is known.
        case symbol

        /// Resolves the presentation: a name with letters is a monogram, anything else the symbol.
        static func resolve(name: String?) -> Presentation {
            ProfileButton.initials(name).map(Presentation.monogram) ?? .symbol
        }

        /// The toolbar item's shared Liquid Glass (iOS 26): hidden behind the monogram, so no ring shows around the
        /// disc; the symbol keeps the system glass like every other bar glyph.
        var sharedBackground: Visibility {
            if case .monogram = self { return .hidden }
            return .automatic
        }
    }

    /// The disc's size and how far it draws past its layout width.
    struct Metrics: Equatable {
        /// The disc's diameter in points.
        let diameter: CGFloat
        /// Points the disc draws past its layout width on each side (the bar's hidden-glass padding), so it fills the
        /// glass circle's place.
        let overhang: CGFloat
        /// A 44 pt material circle shows behind the disc (before iOS 26, where the bar draws no glass).
        let ringed: Bool

        /// The padding a bar puts on each side of an item whose shared glass is hidden (measured by FestivalNativeApps on
        /// iOS 26.5, and again here).
        static let hiddenGlassPadding: CGFloat = 10

        /// Resolves the metrics for the bar the button sits in.
        /// - Parameter liquidGlassBar: The bar draws a glass circle per item (iOS 26).
        /// - Returns: With Liquid Glass, a 44 pt disc ``HassTokens/minTarget`` that overhangs the padding so it is the
        ///   whole circle. Before iOS 26, today's look: the 32 pt disc inside Quick Links' 44 pt material circle (the bar
        ///   has no glass to fill), so both circles stay one size. FestivalNativeApps draws a 30 pt outlined disc
        ///   there; we keep ours because the neighbouring Quick Links circle is the same 44 pt material.
        static func resolve(liquidGlassBar: Bool) -> Metrics {
            liquidGlassBar
                ? Metrics(diameter: HassTokens.minTarget, overhang: hiddenGlassPadding, ringed: false)
                : Metrics(diameter: 32, overhang: 0, ringed: true)
        }

        /// The metrics for the running system.
        static var current: Metrics {
            if #available(iOS 26.0, macOS 26.0, *) { return resolve(liquidGlassBar: true) }
            return resolve(liquidGlassBar: false)
        }
    }

    // MARK: Body

    var body: some View {
        let presentation = grouped ? Presentation.symbol : Presentation.resolve(name: name)
        let metrics = Metrics.current
        Button(action: action) { label(for: presentation, metrics: metrics) }
            .overlay(alignment: .topTrailing) { badge(metrics: metrics) }
            .overlay(alignment: .bottomTrailing) { offlineBadge(metrics: metrics) }
            .accessibilityShowsLargeContentViewer {
                Label("Profile", systemImage: "person.crop.circle")
            }
            .accessibilityLabel("Profile")
            .accessibilityValue(Self.accessibilityValue(name: name, attentionCount: attentionCount, isOffline: isOffline))
            .accessibilityHint("Opens your summary and account")
            .accessibilityIdentifier("nav.profile")
    }

    @ViewBuilder
    private func label(for presentation: Presentation, metrics: Metrics) -> some View {
        switch presentation {
        case let .monogram(initials):
            ZStack {
                // Before iOS 26 the 44 pt material circle shows behind the disc, like Quick Links beside it.
                if metrics.ringed { Color.clear.headerCircle() }
                Text(initials)
                    // 16 pt semibold at the default size, white on the fixed blue (5.6:1). A bar item keeps its size; the
                    // Large Content Viewer shows it bigger (HIG Toolbars, Accessibility), so the initials stop growing
                    // past the disc.
                    .font(.callout.weight(.semibold))
                    .dynamicTypeSize(...DynamicTypeSize.xLarge)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(width: metrics.diameter, height: metrics.diameter)
                    // Fixed deep blue: white text stays above 5:1 in light and dark mode.
                    .background(ProfileButton.fill, in: Circle())
            }
            .frame(width: HassTokens.minTarget, height: HassTokens.minTarget)
            // The bar pads a glass-less item on each side; drawing past the layout width fills that padding.
            .padding(.horizontal, -metrics.overhang)
        case .symbol:
            // On a glass bar the system sizes the symbol's circle (44 pt); a frame made it a 56 pt-wide capsule.
            Image(systemName: "person.crop.circle")
                .font(.title3)
                .foregroundStyle(.primary)
                .modifier(SymbolCircle(ringed: metrics.ringed))
        }
    }

    /// The offline badge on the disc's bottom-trailing edge.
    @ViewBuilder
    private func offlineBadge(metrics: Metrics) -> some View {
        if isOffline {
            Image(systemName: "icloud.slash")
                .font(.system(size: 9, weight: .bold))
                .dynamicTypeSize(...DynamicTypeSize.xLarge)
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Color(white: 0.28), in: Circle())
                .overlay { Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5) }
                .offset(x: metrics.overhang - 2, y: 1)
                .accessibilityLabel("Offline")
                .accessibilityIdentifier("nav.offline")
        }
    }

    /// The attention badge on the disc's top-trailing edge.
    @ViewBuilder
    private func badge(metrics: Metrics) -> some View {
        if let text = ProfileSummary.badgeText(attentionCount) {
            Text(text)
                .font(.caption2.weight(.bold))
                .dynamicTypeSize(...DynamicTypeSize.xLarge)
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .frame(minWidth: 16, minHeight: 16)
                .background(HassTokens.Ink.badge, in: Capsule())
                // Relative to the layout box, which is `overhang` narrower than the disc on each side.
                .offset(x: 4 + metrics.overhang, y: -2)
                .accessibilityHidden(true)
        }
    }
}

/// The material circle behind the person symbol before iOS 26; on iOS 26 the bar's own glass is the circle.
private struct SymbolCircle: ViewModifier {
    var ringed: Bool

    func body(content: Content) -> some View {
        if ringed {
            content.headerCircle()
        } else {
            content
        }
    }
}
