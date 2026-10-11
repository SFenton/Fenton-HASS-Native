import HassDesign
import SwiftUI

// MARK: - Flyout

/// The regular-width navigation panel: an overlay that slides in from the leading edge over a
/// full-window scrim, like the web's `drawer-only` layout and FestivalNativeApps' `FestivalDrawer`.
/// It never pushes or resizes the content (`.agents/design/apple/ipados.md`).
///
/// Closes on a destination, a scrim tap, Escape (`.cancelAction`) or the VoiceOver escape gesture.
struct NavigationFlyout: View {
    @Environment(ShellNavigator.self) private var navigator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var headingFocused: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            if navigator.isFlyoutOpen {
                scrim
                    .transition(.opacity)
                panel
                    .transition(reduceMotion ? .opacity : .move(edge: .leading))
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.3), value: navigator.isFlyoutOpen)
        .onChange(of: navigator.isFlyoutOpen) { _, isOpen in
            if isOpen { headingFocused = true }
        }
    }

    // MARK: - Scrim

    private var scrim: some View {
        Button {
            navigator.dismissFlyout()
        } label: {
            Color.black.opacity(0.32)
                .ignoresSafeArea()
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
        .accessibilityLabel("Close Navigation")
        .accessibilityIdentifier("nav.flyout.scrim")
        // The panel's own rows come first for VoiceOver; the scrim is reachable as a close button after them.
        .accessibilitySortPriority(-1)
    }

    // MARK: - Panel

    private var panel: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: HassTokens.Spacing.xs) {
                    Text("Navigation")
                        .font(.title2.bold())
                        .foregroundStyle(HassTokens.Ink.primary)
                        .padding(.horizontal, HassTokens.Spacing.m)
                        .padding(.bottom, HassTokens.Spacing.s)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($headingFocused)
                        .accessibilityIdentifier("nav.flyout.heading")
                    ForEach(NavigationMenu.primary) { row(for: $0) }
                    // Settings is pinned to the bottom when everything fits; at large text sizes it
                    // scrolls with the rows.
                    Spacer(minLength: HassTokens.Spacing.xl)
                    ForEach(NavigationMenu.footer) { row(for: $0) }
                }
                .padding(HassTokens.Spacing.m)
                .frame(minHeight: proxy.size.height, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(width: NavigationFlyoutMetrics.panelWidth)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: HassTokens.Radius.tile, style: .continuous))
        .padding(NavigationFlyoutMetrics.margin)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nav.flyout")
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { navigator.dismissFlyout() }
    }

    private func row(for section: AppSection) -> some View {
        let isCurrent = navigator.selection == section
        let badge = NavigationMenu.badge(for: section, overdue: navigator.overdueChores)
        return Button {
            navigator.select(section)
        } label: {
            HStack(spacing: HassTokens.Spacing.m) {
                Image(systemName: section.symbol)
                    .font(.body.weight(.semibold))
                    .frame(width: 28)
                    .accessibilityHidden(true)
                Text(section.title)
                    .font(.body.weight(isCurrent ? .semibold : .regular))
                Spacer(minLength: HassTokens.Spacing.s)
                if let badge {
                    Text(badge, format: .number)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, HassTokens.Spacing.s)
                        .padding(.vertical, 2)
                        .background(HassTokens.Tint.security, in: Capsule())
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(isCurrent ? Color.white : HassTokens.Ink.primary)
            .padding(.horizontal, HassTokens.Spacing.m)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background {
                if isCurrent {
                    RoundedRectangle(cornerRadius: HassTokens.Radius.chip, style: .continuous)
                        .fill(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(NavigationMenu.accessibilityLabel(for: section, overdue: navigator.overdueChores))
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .accessibilityIdentifier(section.navigationIdentifier)
    }
}

/// Fixed flyout geometry.
enum NavigationFlyoutMetrics {
    /// Panel width; the web rail is 248 px, widened for 44 pt rows and Dynamic Type.
    static let panelWidth: CGFloat = 300
    /// Gap between the floating panel and the window edges (FestivalNativeApps drawer).
    static let margin: CGFloat = 8
    /// Width of the leading-edge strip that opens the flyout with a swipe.
    static let edgeSwipeWidth: CGFloat = 20
    /// Horizontal travel that opens the flyout.
    static let edgeSwipeDistance: CGFloat = 60

    /// Whether a drag from the leading edge should open the flyout.
    /// - Parameters:
    ///   - startX: Where the drag began, from the leading edge.
    ///   - translation: Total movement.
    static func edgeSwipeOpens(startX: CGFloat, translation: CGSize) -> Bool {
        startX <= edgeSwipeWidth
            && translation.width >= edgeSwipeDistance
            && abs(translation.width) > abs(translation.height)
    }
}

// MARK: - Toolbar button and edge swipe

extension View {
    /// Adds the regular-width Open Navigation toolbar button to a section's root page.
    func sectionRootChrome() -> some View { modifier(SectionRootChrome()) }
}

/// The Open Navigation button (and nothing in tab-bar style).
private struct SectionRootChrome: ViewModifier {
    @Environment(ShellNavigator.self) private var navigator
    @Environment(\.shellNavigationStyle) private var style
    @AccessibilityFocusState private var buttonFocused: Bool

    func body(content: Content) -> some View {
        if style == .flyout {
            content
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        Button {
                            navigator.openFlyout()
                        } label: {
                            Label("Open Navigation", systemImage: "line.3.horizontal")
                        }
                        .accessibilityIdentifier("nav.open")
                        .accessibilityFocused($buttonFocused)
                    }
                }
                .onChange(of: navigator.focusReturnToken) { _, _ in buttonFocused = true }
        } else {
            content
        }
    }
}

extension View {
    /// Opens the flyout with a leading-edge swipe while the selected section is at its root (deeper,
    /// the system's back swipe owns that edge).
    func flyoutEdgeSwipe(_ navigator: ShellNavigator, isEnabled: Bool) -> some View {
        modifier(FlyoutEdgeSwipe(navigator: navigator, isEnabled: isEnabled))
    }
}

/// Implementation of ``SwiftUI/View/flyoutEdgeSwipe(_:isEnabled:)``.
///
/// A simultaneous drag on the whole content rather than a hit-testable strip over the leading edge:
/// a strip took every tap in its 20 pt, including the leading part of Open Navigation and of list rows.
/// Taps never become a drag (16 pt minimum distance), and only a drag that starts inside the edge opens.
private struct FlyoutEdgeSwipe: ViewModifier {
    var navigator: ShellNavigator
    var isEnabled: Bool

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 16, coordinateSpace: .local)
                .onEnded { value in
                    navigator.edgeSwipeEnded(startX: value.startLocation.x, translation: value.translation)
                },
            isEnabled: isEnabled
        )
    }
}

// MARK: - Environment

extension EnvironmentValues {
    /// The root navigation style in effect.
    @Entry var shellNavigationStyle: ShellNavigationStyle = .tabBar
}
