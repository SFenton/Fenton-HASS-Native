import SwiftUI

// MARK: - Geometry

/// Geometry of the fade that keeps scrolling content out from under a page or modal header
/// (pattern: `.agents/patterns/header-edge-fade.md`; owner, 2026-10-13: "Headers should not have the
/// translucent background behind them in pages or modals. Content should fade as it scrolls up to the
/// headers.").
///
/// Ported from FestivalNativeApps' `ModalTopEdgeFade` (`apple/Sources/FestivalUI/Design/ModalTopEdgeFade.swift`):
/// the header (the navigation bar: title, Close, toolbar items) has no band of its own. Content is fully
/// transparent at the header's bottom edge and fades back in over ``rampHeight`` points below it. At rest
/// (scrolled to the top) nothing is dimmed; the fade grows with the first ``rampHeight`` points of scrolling.
public enum HeaderEdgeFade {
    /// Height of the fade below the header (FestivalNativeApps `ScrollEdgeFade.topDistance`, the web
    /// `useScrollMask` `DEFAULT_SIZE` of 40 px).
    public static let rampHeight: CGFloat = 40

    /// Header height from the content's two readings.
    ///
    /// A full-bleed `List` reaches under the bar, so the header is its top safe-area inset and the container
    /// offset is 0. Content laid out below the bar is offset from the container's top by the header and still
    /// reports the same inset, so the readings are not added: the larger one is the header in both layouts.
    ///
    /// - Parameters:
    ///   - safeAreaInset: The content's top safe-area inset.
    ///   - containerOffset: How far the content's top sits below the container's top.
    /// - Returns: The header height; 0 for negative or non-finite readings.
    public static func headerHeight(safeAreaInset: CGFloat, containerOffset: CGFloat) -> CGFloat {
        let readings = [safeAreaInset, containerOffset].filter(\.isFinite)
        return max(0, readings.max() ?? 0)
    }

    /// The band kept clear above the content: the header, but never a page's large title.
    ///
    /// On iOS 26 an expanded large title is drawn with the page's content and counts toward its top inset, so
    /// clearing the whole inset hid the title. The band stops at the inline bar's bottom edge instead: the
    /// smallest inset seen so far (the bar once the title has collapsed) or the window's estimate
    /// (``SwiftUI/EnvironmentValues/headerEdgeCap``), whichever is lower. The large title then fades under the
    /// bar with the rest of the content.
    ///
    /// - Parameters:
    ///   - header: The full header from ``headerHeight(safeAreaInset:containerOffset:)``.
    ///   - smallestInset: The smallest top inset seen on this page; nil before the first reading.
    ///   - cap: The window's estimate of the inline bar's bottom edge; nil where unknown.
    /// - Returns: The height to keep clear, at most `header`.
    public static func clearHeight(header: CGFloat, smallestInset: CGFloat?, cap: CGFloat?) -> CGFloat {
        let limits = [smallestInset, cap].compactMap { $0 }.filter { $0.isFinite && $0 > 0 }
        return max(0, min(header, limits.min() ?? header))
    }

    /// How far the fade has grown.
    ///
    /// - Parameters:
    ///   - scrollOffset: Distance scrolled from the content's resting top (content offset plus top inset);
    ///     negative while pulled down past the top.
    ///   - rampHeight: The ramp's height; 0 is a hard edge as soon as the content scrolls.
    /// - Returns: 0 at rest or pulled down, rising linearly to 1 after `rampHeight` points; 0 for a
    ///   non-finite reading.
    public static func progress(scrollOffset: CGFloat, rampHeight: CGFloat = rampHeight) -> CGFloat {
        guard scrollOffset.isFinite else { return 0 }
        guard rampHeight > 0 else { return scrollOffset > 0 ? 1 : 0 }
        return min(max(scrollOffset / rampHeight, 0), 1)
    }

    /// Mask opacity at the header's bottom edge, where the ramp starts. Above the edge the mask is always
    /// clear, so content never shows under the header.
    ///
    /// - Parameter progress: The fade's growth from ``progress(scrollOffset:rampHeight:)``.
    /// - Returns: 1 at rest (content just below the header fully drawn), 0 once scrolled a full ramp.
    public static func edgeOpacity(progress: CGFloat) -> CGFloat {
        guard progress.isFinite else { return 1 }
        return 1 - min(max(progress, 0), 1)
    }

    /// The ramp for the reader's settings: Reduce Transparency or Increase Contrast turns it into a hard edge
    /// (content cut cleanly at the header, never dimmed; FestivalNativeApps scroll-edge R7).
    ///
    /// - Parameters:
    ///   - reduceTransparency: System Reduce Transparency.
    ///   - increaseContrast: System Increase Contrast.
    ///   - tracksScroll: The system reports the scroll position (iOS 18 and later); without it the ramp
    ///     could not grow from zero at rest, so it is a hard edge.
    /// - Returns: ``rampHeight`` or 0.
    public static func ramp(reduceTransparency: Bool, increaseContrast: Bool, tracksScroll: Bool) -> CGFloat {
        reduceTransparency || increaseContrast || !tracksScroll ? 0 : rampHeight
    }
}

// MARK: - Environment

extension EnvironmentValues {
    /// The window's estimate of where the inline navigation bar ends (status bar plus a compact bar), so a page's
    /// expanded large title is not taken for header (``HeaderEdgeFade/clearHeight(header:smallestInset:cap:)``).
    /// Set by the app's root; nil keeps the whole measured header clear.
    @Entry public var headerEdgeCap: CGFloat?
}

// MARK: - Modifier

extension View {
    /// Keeps this scrolling content out from under its navigation bar: hides the bar's own background (the
    /// iOS 26 scroll-edge effect and the bar material) and fades the content to clear at the bar's bottom edge
    /// (``HeaderEdgeFade``). Pages get it from `pageChrome()` and modals from `HassModal` / `modalChrome()`;
    /// apply it inside the `NavigationStack`, on the view that owns the toolbar.
    public func headerEdgeFade() -> some View {
        modifier(HeaderEdgeFadeModifier())
    }
}

/// Implementation of ``SwiftUI/View/headerEdgeFade()``.
struct HeaderEdgeFadeModifier: ViewModifier {
    /// The content's own coordinate space; global coordinates would include a sheet's presentation transform.
    private nonisolated static let space = "hass.headerEdgeFade"

    @State private var safeAreaInset: CGFloat = 0
    @State private var containerOffset: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0
    @State private var smallestInset: CGFloat?
    @Environment(\.headerEdgeCap) private var cap
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private var tracksScroll: Bool {
        if #available(iOS 18.0, macOS 15.0, watchOS 11.0, *) { return true }
        return false
    }

    private var rampHeight: CGFloat {
        HeaderEdgeFade.ramp(reduceTransparency: reduceTransparency, increaseContrast: contrast == .increased,
                            tracksScroll: tracksScroll)
    }

    private var headerHeight: CGFloat {
        HeaderEdgeFade.clearHeight(
            header: HeaderEdgeFade.headerHeight(safeAreaInset: safeAreaInset, containerOffset: containerOffset),
            smallestInset: smallestInset, cap: cap
        )
    }

    func body(content: Content) -> some View {
        content
            .modifier(ScrollOffsetReader { scrollOffset = $0 })
            .modifier(HeaderBackgroundHidden())
            .background {
                Color.clear
                    .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top.rounded() } action: { inset in
                        safeAreaInset = inset
                        if inset > 0, inset < (smallestInset ?? .infinity) { smallestInset = inset }
                    }
                    .accessibilityHidden(true)
            }
            .background {
                Color.clear
                    .onGeometryChange(for: CGFloat.self) { -$0.frame(in: .named(Self.space)).minY.rounded() } action: {
                        containerOffset = $0
                    }
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
            }
            .mask {
                VStack(spacing: 0) {
                    Color.clear.frame(height: headerHeight)
                    LinearGradient(
                        colors: [
                            .black.opacity(HeaderEdgeFade.edgeOpacity(
                                progress: HeaderEdgeFade.progress(scrollOffset: scrollOffset, rampHeight: rampHeight)
                            )),
                            .black,
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: rampHeight)
                    Color.black
                }
                // Reach under the header so the clear band covers it.
                .ignoresSafeArea()
            }
            .coordinateSpace(.named(Self.space))
    }
}

/// Reports the enclosed scroll view's distance from its resting top (iOS 18 / macOS 15 and later).
private struct ScrollOffsetReader: ViewModifier {
    var action: (CGFloat) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, macOS 15.0, watchOS 11.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { geometry in
                // Whole points, clamped to the ramp: only changes that move the mask reach the action.
                min(max((geometry.contentOffset.y + geometry.contentInsets.top).rounded(), -1), HeaderEdgeFade.rampHeight + 1)
            } action: { _, offset in
                action(offset)
            }
        } else {
            content
        }
    }
}

/// Hides the header's own background: the iOS 26 top scroll-edge effect and the navigation bar material.
private struct HeaderBackgroundHidden: ViewModifier {
    func body(content: Content) -> some View {
        #if os(watchOS)
        content
        #else
        if #available(iOS 26.0, macOS 26.0, *) {
            content
                .scrollEdgeEffectHidden(true, for: .top)
                #if os(iOS)
                .toolbarBackground(.hidden, for: .navigationBar)
                #endif
        } else {
            content
                #if os(iOS)
                .toolbarBackground(.hidden, for: .navigationBar)
                #endif
        }
        #endif
    }
}
