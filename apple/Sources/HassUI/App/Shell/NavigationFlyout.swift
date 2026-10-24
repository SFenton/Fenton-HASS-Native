import HassCore
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
        .motionSafeAnimation(MotionTokens.standard, reduced: MotionTokens.quick, value: navigator.isFlyoutOpen)
        .onChange(of: navigator.isFlyoutOpen) { _, isOpen in
            if isOpen { headingFocused = true }
        }
    }

    // MARK: - Scrim

    private var scrim: some View {
        ZStack(alignment: .leading) {
            // The dimming layer: drawing only. Covers the whole window, the status bar area included, so the
            // content behind the drawer darkens the same under the top safe area as in the body.
            Color.black.opacity(0.32)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            // The close target covers only the area beside the panel: a full-window button won the
            // accessibility hit test over the panel's rows, so touch exploration read "Close Navigation"
            // on top of them (XCUITest: rows not hittable).
            Button {
                navigator.dismissFlyout()
            } label: {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea(edges: [.horizontal, .bottom])
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .padding(.leading, NavigationFlyoutMetrics.panelWidth)
            .accessibilityLabel("Close Navigation")
            .accessibilityIdentifier("nav.flyout.scrim")
            // The panel's own rows come first for VoiceOver; the close target is reachable after them.
            .accessibilitySortPriority(-1)
        }
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
                }
                .padding(HassTokens.Spacing.m)
                .frame(minHeight: proxy.size.height, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(width: NavigationFlyoutMetrics.panelWidth)
        // A full-height drawer: the blur runs under the status bar, the home indicator and any leading inset, while
        // the rows stay inside the safe area.
        .background {
            UnevenRoundedRectangle(bottomTrailingRadius: HassTokens.Radius.tile, topTrailingRadius: HassTokens.Radius.tile, style: .continuous)
                .fill(.regularMaterial)
                .ignoresSafeArea()
        }
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
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, HassTokens.Spacing.s)
                        .padding(.vertical, 2)
                        .background(HassTokens.Ink.badge, in: Capsule())
                        .accessibilityHidden(true)
                }
            }
            // Primary ink on an accent tint, like Settings' selected row: white on the light accent
            // measured 2.5:1 in the iPad audit.
            .foregroundStyle(HassTokens.Ink.primary)
            .padding(.horizontal, HassTokens.Spacing.m)
            // Vertical padding so the row grows with Dynamic Type instead of resting on its minimum.
            .padding(.vertical, HassTokens.Spacing.s)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background {
                if isCurrent {
                    RoundedRectangle(cornerRadius: HassTokens.Radius.chip, style: .continuous)
                        .fill(Color.accentColor.opacity(0.18))
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


extension View {
    /// Opens the flyout with a leading-edge swipe while the selected section is at its root (deeper,
    /// the system's back swipe owns that edge).
    func flyoutEdgeSwipe(_ navigator: ShellNavigator, isEnabled: Bool) -> some View {
        modifier(FlyoutEdgeSwipe(navigator: navigator, isEnabled: isEnabled))
    }
}

/// Implementation of ``SwiftUI/View/flyoutEdgeSwipe(_:isEnabled:)``.
///
/// iOS 18+: a UIKit screen-edge pan, like the system back swipe. Once it recognizes it cancels the
/// touch in the content, so a swipe that starts on a control (a Home camera tile at the leading edge of
/// the landscape iPhone Duo) opens only the flyout; a SwiftUI drag ran alongside the control and opened
/// the camera too. Taps never reach it, so nothing at the edge loses its taps (an earlier hit-testable
/// 20 pt strip took them). iOS 17 and macOS keep a simultaneous drag.
private struct FlyoutEdgeSwipe: ViewModifier {
    var navigator: ShellNavigator
    var isEnabled: Bool
    @Environment(\.layoutDirection) private var layoutDirection

    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 18.0, *) {
            content.gesture(
                ScreenEdgePan(edge: layoutDirection == .rightToLeft ? .right : .left, isEnabled: isEnabled) { translation in
                    navigator.edgeSwipeEnded(startX: 0, translation: translation)
                }
            )
        } else {
            dragFallback(content)
        }
        #else
        dragFallback(content)
        #endif
    }

    private func dragFallback(_ content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 16, coordinateSpace: .local)
                .onEnded { value in
                    navigator.edgeSwipeEnded(startX: value.startLocation.x, translation: value.translation)
                },
            isEnabled: isEnabled
        )
    }
}

#if os(iOS)
/// A `UIScreenEdgePanGestureRecognizer` on the leading edge that reports its translation when it ends,
/// flipped so a swipe away from the leading edge is positive in either layout direction.
@available(iOS 18.0, *)
private struct ScreenEdgePan: UIGestureRecognizerRepresentable {
    var edge: UIRectEdge
    var isEnabled: Bool
    var onEnded: (CGSize) -> Void

    func makeUIGestureRecognizer(context: Context) -> UIScreenEdgePanGestureRecognizer {
        let recognizer = UIScreenEdgePanGestureRecognizer()
        recognizer.edges = edge
        recognizer.isEnabled = isEnabled
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UIScreenEdgePanGestureRecognizer, context: Context) {
        recognizer.edges = edge
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIScreenEdgePanGestureRecognizer, context: Context) {
        guard recognizer.state == .ended else { return }
        let raw = recognizer.translation(in: recognizer.view)
        onEnded(CGSize(width: edge == .right ? -raw.x : raw.x, height: raw.y))
    }
}
#endif

// MARK: - Environment

extension EnvironmentValues {
    /// The root navigation style in effect.
    @Entry var shellNavigationStyle: ShellNavigationStyle = .tabBar
    /// Where the shell puts its menu and Quick Links buttons (``ShellChrome``).
    @Entry var shellChrome = ShellChrome(showsMenuButton: false, titleInHeader: true)
    /// The system moves bar items into a vertical bar (the iPhone Duo, folded or unfolded in landscape), set by
    /// ``SwiftUI/View/observesDeviceSignals()`` from `toolbarVerticalEdge` (iOS 27.1). The header leaves out its fixed
    /// spacer there: HIG Designing for iPhone Duo, "system spacing adapts, so don't add fixed spacing".
    @Entry var shellInVerticalBar = false
}
