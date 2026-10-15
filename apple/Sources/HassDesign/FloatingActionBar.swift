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

    /// Creates a bar.
    public init(actions: [FloatingAction], search: FloatingSearch? = nil) {
        self.actions = actions
        self.search = search
    }

    public var body: some View {
        HStack(spacing: HassTokens.Spacing.s) {
            if let search {
                if search.isExpanded.wrappedValue {
                    expandedSearch(search)
                } else if typeSize.isAccessibilitySize {
                    // At accessibility sizes the prompt would not fit beside the other actions: the magnifier alone,
                    // still named by the prompt.
                    circleButton(id: "search", title: search.prompt, symbol: "magnifyingglass",
                                 isActive: !search.text.wrappedValue.isEmpty) { open(search) }
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
        .padding(.horizontal, HassTokens.Spacing.l)
        .padding(.bottom, HassTokens.Spacing.s)
        // Reduce Motion: the search capsule swaps in place without the spring.
        .animation(reduceMotion ? nil : .snappy, value: search?.isExpanded.wrappedValue)
    }

    private func open(_ search: FloatingSearch) {
        search.isExpanded.wrappedValue = true
        searchFocused = true
    }

    // MARK: Buttons

    private func capsuleButton(_ action: FloatingAction) -> some View {
        Button(action: action.action) {
            Label(action.title, systemImage: action.symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, HassTokens.Spacing.l + 2)
                .frame(minHeight: Self.size)
                .background {
                    if action.isProminent {
                        Capsule().fill(Self.tint)
                    }
                }
                .modifier(GlassUnlessProminent(isProminent: action.isProminent, shape: Capsule()))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(action.isProminent ? 0.35 : 0.2), radius: 13, y: 5)
        .accessibilityAddTraits(action.isActive ? [.isSelected] : [])
        .accessibilityIdentifier("fab.\(action.id)")
    }

    private func circleButton(id: String, title: String, symbol: String, isActive: Bool, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Image(systemName: symbol)
                .font(.title3.weight(.medium))
                .foregroundStyle(isActive ? Self.activeGlyph : .white)
                .frame(width: Self.size, height: Self.size)
                .background {
                    if isActive { Circle().fill(Self.activeTint) }
                }
                .modifier(GlassUnlessProminent(isProminent: isActive, shape: Circle()))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(isActive ? 0.35 : 0.2), radius: 11, y: 4)
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
            .foregroundStyle(query.isEmpty ? HassTokens.Surface.secondaryOnWash : .white)
            .padding(.horizontal, HassTokens.Spacing.l)
            .frame(maxWidth: .infinity, minHeight: Self.size)
            .navigationGlass(in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.2), radius: 11, y: 4)
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
        .frame(minHeight: Self.size)
        .navigationGlass(in: Capsule())
        .shadow(color: .black.opacity(0.2), radius: 11, y: 4)
        .frame(maxWidth: .infinity)
    }

    /// Button height: comfortably above the 44 pt minimum, like the web's 56 px FAB and G's 52 pt toolbar circles.
    static let size: CGFloat = 52
}

/// Glass behind a bar button, unless it carries its own solid fill (the prominent capsule, an active circle).
private struct GlassUnlessProminent<S: Shape>: ViewModifier {
    var isProminent: Bool
    var shape: S

    func body(content: Content) -> some View {
        if isProminent {
            content
        } else {
            content.navigationGlass(in: shape)
        }
    }
}

public extension View {
    /// Pins floating actions to the bottom trailing corner and insets the page so content scrolls clear of them.
    /// No actions and no search draws nothing.
    ///
    /// On iOS 26 and later the bar is a `safeAreaBar` with a hard scroll edge effect, so rows scrolled under the
    /// buttons are covered instead of showing through at low contrast (HIG: Materials › Scroll edge effects).
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
            safeAreaBar(edge: .bottom, alignment: .trailing, spacing: 0) { bar }
                .scrollEdgeEffectStyle(.hard, for: .bottom)
        } else {
            safeAreaInset(edge: .bottom, alignment: .trailing, spacing: 0) { bar }
        }
        #endif
    }
}
