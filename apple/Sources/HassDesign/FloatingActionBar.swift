import SwiftUI

/// One floating action: a labeled capsule or an icon-only circle (web `FloatingActionButton`).
public struct FloatingAction: Identifiable {
    /// Stable id; also the accessibility identifier suffix (`fab.<id>`).
    public var id: String
    /// Visible label, and the accessibility label of an icon-only action.
    public var title: String
    /// SF Symbol.
    public var symbol: String
    /// Draws the title next to the symbol; icon-only actions keep it for VoiceOver.
    public var showsTitle: Bool
    /// Applied state (e.g. a filter is set): drawn in ``FloatingActionBar/activeTint`` and read as selected.
    public var isActive: Bool
    public var action: () -> Void

    /// Creates an action.
    public init(id: String, title: String, symbol: String, showsTitle: Bool = true, isActive: Bool = false, action: @escaping () -> Void) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.showsTitle = showsTitle
        self.isActive = isActive
        self.action = action
    }
}

/// An expandable search field that sits in the bar (web recipe and inventory search FABs).
public struct FloatingSearch {
    public var text: Binding<String>
    public var isExpanded: Binding<Bool>
    /// Placeholder and accessibility label, e.g. "Search recipes".
    public var prompt: String

    /// Creates a search field.
    public init(text: Binding<String>, isExpanded: Binding<Bool>, prompt: String) {
        self.text = text
        self.isExpanded = isExpanded
        self.prompt = prompt
    }
}

/// Floating page actions pinned to the bottom trailing corner (pattern: `.agents/patterns/floating-actions.md`).
///
/// Apply with ``SwiftUI/View/floatingActionBar(_:search:)``: it insets the page's safe area so the last row
/// scrolls clear of the bar. An expanded search field takes the bar's full width and hides the other actions,
/// like the web.
public struct FloatingActionBar: View {
    public var actions: [FloatingAction]
    public var search: FloatingSearch?

    /// The web's `CHORE_BLUE` (0, 154, 199) darkened to (0, 110, 145) so white labels reach 5.8:1.
    public static let tint = Color(red: 0, green: 110 / 255, blue: 145 / 255)
    /// The web's active brown (155, 110, 64) darkened to (135, 95, 55) so white labels reach 5.6:1.
    public static let activeTint = Color(red: 135 / 255, green: 95 / 255, blue: 55 / 255)

    @FocusState private var searchFocused: Bool

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
                } else {
                    circleButton(id: "search", title: search.prompt, symbol: "magnifyingglass", isActive: !search.text.wrappedValue.isEmpty) {
                        search.isExpanded.wrappedValue = true
                        searchFocused = true
                    }
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
        .animation(.snappy, value: search?.isExpanded.wrappedValue)
    }

    // MARK: Buttons

    private func capsuleButton(_ action: FloatingAction) -> some View {
        Button(action: action.action) {
            Label(action.title, systemImage: action.symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, HassTokens.Spacing.l)
                .frame(minHeight: Self.size)
                .background(action.isActive ? Self.activeTint : Self.tint, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
        .accessibilityAddTraits(action.isActive ? [.isSelected] : [])
        .accessibilityIdentifier("fab.\(action.id)")
    }

    private func circleButton(id: String, title: String, symbol: String, isActive: Bool, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: Self.size, height: Self.size)
                .background(isActive ? Self.activeTint : Self.tint, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
        .accessibilityIdentifier("fab.\(id)")
    }

    private func expandedSearch(_ search: FloatingSearch) -> some View {
        HStack(spacing: HassTokens.Spacing.s) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(HassTokens.Ink.secondary)
                .accessibilityHidden(true)
            TextField(search.prompt, text: search.text)
                .focused($searchFocused)
                .submitLabel(.search)
                .foregroundStyle(HassTokens.Ink.primary)
                .accessibilityIdentifier("fab.search.field")
            Button {
                search.text.wrappedValue = ""
                search.isExpanded.wrappedValue = false
                searchFocused = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(HassTokens.Ink.secondary)
                    .frame(minWidth: HassTokens.minTarget, minHeight: HassTokens.minTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close Search")
            .accessibilityIdentifier("fab.search.close")
        }
        .padding(.leading, HassTokens.Spacing.l)
        .frame(minHeight: Self.size)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Self.tint.opacity(0.6), lineWidth: 1))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
        .frame(maxWidth: .infinity)
    }

    /// Button height: comfortably above the 44 pt minimum, like the web's 56 px FAB.
    static let size: CGFloat = 52
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
