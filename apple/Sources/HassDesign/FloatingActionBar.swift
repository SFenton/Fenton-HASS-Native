import SwiftUI

/// One floating action: a labeled capsule or an icon-only glass circle (web `FloatingActionButton`).
public struct FloatingAction: Identifiable {
    /// Stable id; also the accessibility identifier suffix (`fab.<id>`).
    public var id: String
    /// Visible label, and the accessibility label of an icon-only action.
    public var title: String
    /// SF Symbol.
    public var symbol: String
    /// Draws the title next to the symbol; icon-only actions keep it for VoiceOver.
    public var showsTitle: Bool
    /// Applied state (e.g. a filter is set): drawn on the light active fill and read as selected.
    public var isActive: Bool
    /// A labeled action that is the page's one primary action ("Add Task") fills with G's `#0071E3`; otherwise it is
    /// a glass capsule ("Scan Item" on an empty pantry). Icon-only actions are always glass.
    public var isProminent: Bool
    public var action: () -> Void

    /// Creates an action.
    public init(id: String, title: String, symbol: String, showsTitle: Bool = true, isActive: Bool = false,
                isProminent: Bool = true, action: @escaping () -> Void) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.showsTitle = showsTitle
        self.isActive = isActive
        self.isProminent = isProminent
        self.action = action
    }
}

/// A search field that sits in the bar (web recipe and inventory search FABs).
public struct FloatingSearch {
    public var text: Binding<String>
    public var isExpanded: Binding<Bool>
    /// Placeholder and accessibility label, e.g. "Search Recipes".
    public var prompt: String

    /// Creates a search field.
    public init(text: Binding<String>, isExpanded: Binding<Bool>, prompt: String) {
        self.text = text
        self.isExpanded = isExpanded
        self.prompt = prompt
    }
}

/// Floating page actions along the bottom edge (pattern: `.agents/patterns/floating-actions.md`), direction G's page
/// bottom toolbar (`.agents/design/direction-g.md`, Layers: Liquid Glass is for "page bottom toolbars").
///
/// Apply with ``SwiftUI/View/floatingActionBar(_:search:)``: it insets the page's safe area so the last row
/// scrolls clear of the bar. Search is a glass capsule that fills the bar's leading space, with the other actions as
/// 52 pt glass circles trailing it (mockups n6 Recipes and All Food). Tapping it opens the field, which then takes the
/// bar's full width and hides the other actions, like the web. A page's primary labeled action ("Add Task") is a
/// `#0071E3` capsule (n5 Chores).
public struct FloatingActionBar: View {
    public var actions: [FloatingAction]
    public var search: FloatingSearch?

    /// The prominent capsule's fill: G's `#0071E3`, 4.6:1 under white (``HassTokens/Ink/actionFill``).
    public static let tint = HassTokens.Ink.actionFill
    /// An active circle's fill (a sort or filter is applied): system gray 6 light, `#F2F2F7`, under a black glyph
    /// (mockup n6, `.n6-tool.active`).
    public static let activeTint = Color(rgb: 0xF2F2F7)
    /// The glyph on an active circle.
    static let activeGlyph = Color.black

    @FocusState private var searchFocused: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The circles' size, growing with the glyph (Dynamic Type) up to one and a half times the base, so the bar's
    /// buttons grow with the text but never take the screen.
    @ScaledMetric(relativeTo: .title3) private var scaledSize: CGFloat = FloatingActionBar.size

    private var buttonSize: CGFloat { min(scaledSize, Self.size * Self.maxGrowth) }

    /// Creates a bar.
    public init(actions: [FloatingAction], search: FloatingSearch? = nil) {
        self.actions = actions
        self.search = search
    }

    public var body: some View {
        Group {
            if typeSize.isAccessibilitySize && search?.isExpanded.wrappedValue != true {
                accessibilityLayout
            } else {
                standardLayout
            }
        }
        .padding(.horizontal, HassTokens.Spacing.l)
        .padding(.bottom, HassTokens.Spacing.s)
        // Reduce Motion: the search capsule swaps in place without the spring.
        .motionSafeAnimation(MotionTokens.standard, value: search?.isExpanded.wrappedValue)
    }

    /// One row: the search field fills the leading space, then the other actions.
    private var standardLayout: some View {
        HStack(spacing: HassTokens.Spacing.s) {
            if let search {
                if search.isExpanded.wrappedValue {
                    expandedSearch(search)
                } else {
                    collapsedSearch(search)
                }
            }
            if search?.isExpanded.wrappedValue != true {
                ForEach(actions) { action in
                    if action.showsTitle {
                        capsuleButton(action)
                    } else {
                        circleButton(id: action.id, title: action.title, symbol: action.symbol, isActive: action.isActive, perform: action.action)
                    }
                }
            }
        }
    }

    /// At accessibility text sizes one row cannot hold the field, the circles and a labelled capsule: the capsule's label
    /// wrapped a letter to a line and the glyphs ran over the page (folded iPhone Duo, AX5, 2026-10-16). The labelled
    /// actions take a full-width row of their own, where the title wraps by word, and the search magnifier and the circles
    /// sit in a row beneath, trailing, each at least 44 pt and growing with the text (HIG, Accessibility › Dynamic Type:
    /// reflow rather than truncate; Buttons: keep hit targets large).
    private var accessibilityLayout: some View {
        VStack(alignment: .trailing, spacing: HassTokens.Spacing.s) {
            ForEach(actions.filter(\.showsTitle)) { action in
                capsuleButton(action, fillsWidth: true)
            }
            HStack(spacing: HassTokens.Spacing.s) {
                Spacer(minLength: 0)
                if let search {
                    circleButton(id: "search", title: search.prompt, symbol: "magnifyingglass",
                                 isActive: !search.text.wrappedValue.isEmpty) { open(search) }
                }
                ForEach(actions.filter { !$0.showsTitle }) { action in
                    circleButton(id: action.id, title: action.title, symbol: action.symbol, isActive: action.isActive, perform: action.action)
                }
            }
        }
    }

    private func open(_ search: FloatingSearch) {
        search.isExpanded.wrappedValue = true
        searchFocused = true
    }

    // MARK: Buttons

    private func capsuleButton(_ action: FloatingAction, fillsWidth: Bool = false) -> some View {
        Button(action: action.action) {
            Label(action.title, systemImage: action.symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, HassTokens.Spacing.l + 2)
                .padding(.vertical, fillsWidth ? HassTokens.Spacing.s : 0)
                .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: buttonSize)
                // Liquid Glass in both cases (owner, 2026-10-16): the primary action is blue-tinted glass, a secondary one
                // clear of tint, so the page shows through the bar.
                .modifier(BarGlass(tint: action.isProminent ? Self.tint : nil, shape: Capsule()))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.title)
        .accessibilityAddTraits(action.isActive ? [.isSelected] : [])
        .accessibilityIdentifier("fab.\(action.id)")
    }

    private func circleButton(id: String, title: String, symbol: String, isActive: Bool, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Image(systemName: symbol)
                .font(.title3.weight(.medium))
                .stateForeground("FloatingActionBar", isActive ? Self.activeGlyph : Color.white)
                .frame(width: buttonSize, height: buttonSize)
                .modifier(BarGlass(tint: isActive ? Self.activeTint : nil, shape: Circle()))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
        .accessibilityIdentifier("fab.\(id)")
    }

    /// The closed search field: a glass capsule with the magnifier and the prompt, or the query once one is typed.
    private func collapsedSearch(_ search: FloatingSearch) -> some View {
        let query = search.text.wrappedValue
        return Button { open(search) } label: {
            HStack(spacing: HassTokens.Spacing.s) {
                Image(systemName: "magnifyingglass")
                    .font(.body.weight(.medium))
                    .accessibilityHidden(true)
                Text(query.isEmpty ? search.prompt : query)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.body)
            .stateForeground("FloatingActionBar", query.isEmpty ? HassTokens.Surface.secondaryOnWash : Color.white)
            .padding(.horizontal, HassTokens.Spacing.l)
            .frame(maxWidth: .infinity, minHeight: buttonSize)
            .modifier(BarGlass(tint: nil, shape: Capsule()))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(search.prompt)
        .accessibilityValue(query)
        .accessibilityAddTraits(query.isEmpty ? [] : [.isSelected])
        .accessibilityIdentifier("fab.search")
    }

    private func expandedSearch(_ search: FloatingSearch) -> some View {
        HStack(spacing: HassTokens.Spacing.s) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(HassTokens.Surface.secondaryOnWash)
                .accessibilityHidden(true)
            TextField(search.prompt, text: search.text)
                .focused($searchFocused)
                .submitLabel(.search)
                .foregroundStyle(.white)
                .accessibilityIdentifier("fab.search.field")
            Button {
                search.text.wrappedValue = ""
                search.isExpanded.wrappedValue = false
                searchFocused = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(HassTokens.Surface.secondaryOnWash)
                    .frame(minWidth: HassTokens.minTarget, minHeight: HassTokens.minTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close Search")
            .accessibilityIdentifier("fab.search.close")
        }
        .padding(.leading, HassTokens.Spacing.l)
        .frame(minHeight: buttonSize)
        .modifier(BarGlass(tint: nil, shape: Capsule(), isInteractive: false))
        .frame(maxWidth: .infinity)
    }

    /// Button height: comfortably above the 44 pt minimum, like the web's 56 px FAB and G's 52 pt toolbar circles.
    static let size: CGFloat = 52
    /// How far the buttons grow with Dynamic Type: 1.5 times the base size.
    static let maxGrowth: CGFloat = 1.5
}

/// Liquid Glass behind a bar button (HIG, Materials: "Use Liquid Glass for controls and navigation … floating above
/// content. Let content scroll and peek through while preserving control and navigation legibility"). An optional tint
/// colours it (the primary action's blue, an applied sort or filter's light fill); the interactive variant lifts and
/// shimmers under a touch. Below iOS 26 it is a thin material with the tint laid over it.
private struct BarGlass<S: Shape>: ViewModifier {
    var tint: Color?
    var shape: S
    var isInteractive = true

    /// Opacity of the tint over the thin material when there is no glass.
    private static var fallbackTintOpacity: Double { 0.88 }

    func body(content: Content) -> some View {
        #if os(watchOS)
        content.background(.ultraThinMaterial, in: shape)
        #else
        // An applied sort or filter, or a primary action, changes the tint: it cross-fades (`MotionTokens.state`).
        if #available(iOS 26.0, macOS 26.0, *), !PerfSwitches.isOff(.glassBar) {
            content.glassEffect(glass, in: shape)
                .stateColorTransition("FloatingActionBar", value: tint)
        } else {
            content.background {
                shape.fill(.ultraThinMaterial)
                if let tint { shape.fill(tint.opacity(Self.fallbackTintOpacity)) }
            }
            .stateColorTransition("FloatingActionBar", value: tint)
        }
        #endif
    }

    #if !os(watchOS)
    @available(iOS 26.0, macOS 26.0, *)
    private var glass: Glass {
        var glass = Glass.regular
        // Tinted glass is iOS only: a tint blanks the whole macOS hosted window the unit tests snapshot (every pixel one
        // colour, measured 2026-10-17 on macOS 27), while the same glass untinted draws; iOS draws it correctly.
        #if os(iOS)
        if let tint { glass = glass.tint(tint) }
        #endif
        return isInteractive ? glass.interactive() : glass
    }
    #endif
}

public extension View {
    /// Pins floating actions to the bottom trailing corner and insets the page so content scrolls clear of them.
    /// No actions and no search draws nothing.
    ///
    /// On iOS 26 and later the bar is a `safeAreaBar` with a soft bottom scroll edge effect: the buttons are Liquid
    /// Glass, rows scroll up into and under them and show through, and the bar's height is added to the scroll view's
    /// safe area, so the last row can always scroll clear of it (HIG: Materials; Scroll views › Scroll edge effects).
    @ViewBuilder
    func floatingActionBar(_ actions: [FloatingAction], search: FloatingSearch? = nil) -> some View {
        let bar = Group {
            if !actions.isEmpty || search != nil {
                FloatingActionBar(actions: actions, search: search)
            }
        }
        #if os(watchOS)
        safeAreaInset(edge: .bottom, alignment: .trailing, spacing: 0) { bar }
        #else
        if #available(iOS 26, macOS 26, *) {
            if PerfSwitches.isOff(.scrollEdge) {
                safeAreaBar(edge: .bottom, alignment: .trailing, spacing: 0) { bar }
            } else {
                safeAreaBar(edge: .bottom, alignment: .trailing, spacing: 0) { bar }
                    .scrollEdgeEffectStyle(.soft, for: .bottom)
            }
        } else {
            safeAreaInset(edge: .bottom, alignment: .trailing, spacing: 0) { bar }
        }
        #endif
    }
}
