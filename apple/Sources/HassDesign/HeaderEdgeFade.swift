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

    /// The offset the fade tracks, from a scroll view's own readings: whole points, clamped to the ramp so only changes that
    /// move the mask are ever reported.
    ///
    /// - Parameters:
    ///   - contentOffset: The scroll view's vertical content offset.
    ///   - topInset: Its top content inset (the bar the content rests below).
    ///   - rampHeight: The ramp's height.
    /// - Returns: The distance scrolled from the resting top, -1 when pulled down, at most `rampHeight + 1`.
    public static func trackedOffset(contentOffset: CGFloat, topInset: CGFloat, rampHeight: CGFloat = rampHeight) -> CGFloat {
        min(max((contentOffset + topInset).rounded(), -1), rampHeight + 1)
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

    @ViewBuilder
    func body(content: Content) -> some View {
        if PerfSwitches.isOff(.headerFade) {
            // An A/B run without the fade (`FENTON_PERF_DISABLE=headerFade`); the bar's own background stays hidden.
            content.modifier(HeaderBackgroundHidden())
        } else {
            faded(content)
        }
    }

    private func faded(_ content: Content) -> some View {
        // The two halves can each be turned off for an A/B run (`FENTON_PERF_DISABLE=fadeMask,fadeReaders`); a normal launch
        // has both.
        let reads = !PerfSwitches.isOff(.fadeReaders) && !PerfSwitches.isOff(.fadeGeometry)
        let readsScroll = !PerfSwitches.isOff(.fadeReaders) && !PerfSwitches.isOff(.fadeScroll)
        return content
            .modifier(ScrollOffsetReader(isEnabled: readsScroll) { scrollOffset = $0 })
            .background {
                #if os(iOS)
                if readsScroll { UIKitScrollOffset { scrollOffset = $0 }.frame(width: 0, height: 0).accessibilityHidden(true) }
                #endif
            }
            .modifier(HeaderBackgroundHidden())
            .background {
                if reads {
                    Color.clear
                        // A new size (rotation, fold, resize) starts over: the bar's height may have changed.
                        .onGeometryChange(for: CGSize.self) { CGSize(width: $0.size.width.rounded(), height: $0.size.height.rounded()) } action: { _ in
                            smallestInset = nil
                        }
                        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top.rounded() } action: { inset in
                            safeAreaInset = inset
                            if inset > 0, inset < (smallestInset ?? .infinity) { smallestInset = inset }
                        }
                        .accessibilityHidden(true)
                }
            }
            .background {
                if reads {
                    Color.clear
                        .onGeometryChange(for: CGFloat.self) { -$0.frame(in: .named(Self.space)).minY.rounded() } action: {
                            containerOffset = $0
                        }
                        .ignoresSafeArea()
                        .accessibilityHidden(true)
                }
            }
            .mask {
                if PerfSwitches.isOff(.fadeMask) {
                    Color.black.ignoresSafeArea()
                } else {
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
            }
            .coordinateSpace(.named(Self.space))
    }
}

/// Reports the enclosed scroll view's distance from its resting top (iOS 18 / macOS 15 and later).
private struct ScrollOffsetReader: ViewModifier {
    /// False in an A/B run without the readers (``PerfSwitches/Layer/fadeReaders``).
    var isEnabled: Bool
    var action: (CGFloat) -> Void

    func body(content: Content) -> some View {
        // iOS reads the offset from UIKit (``UIKitScrollOffset``): `onScrollGeometryChange` makes SwiftUI update the page's
        // view graph on every frame of a scroll, which cost a `List` page a fifth to a third of its main-thread time.
        #if os(iOS)
        content
        #else
        if isEnabled, #available(iOS 18.0, macOS 15.0, watchOS 11.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { geometry in
                // Whole points, clamped to the ramp: only changes that move the mask reach the action.
                HeaderEdgeFade.trackedOffset(contentOffset: geometry.contentOffset.y, topInset: geometry.contentInsets.top)
            } action: { _, offset in
                action(offset)
            }
        } else {
            content
        }
        #endif
    }
}

#if os(iOS)
/// Reports the page's scroll offset from UIKit, so a scroll never makes SwiftUI update the page's view graph.
///
/// `onScrollGeometryChange` observes the scroll geometry through the graph: every frame of a scroll was a graph update for
/// the whole page, whether or not the value it reads changed (Time Profiler, Settings and Chores on the simulator: graph
/// updates 23% to 10% of the main thread's samples without it, 27% less main-thread time and 40% fewer instructions per
/// 1000 pt). A key-value observer on the scroll view's `contentOffset` costs a closure call per frame and writes to
/// SwiftUI only when the clamped, rounded value changes, which is the first 40 points of a scroll.
///
/// The probe view sits in the page's background, finds the page's vertical scroll view next to it and observes that. Until it
/// is found (the first layout) the fade rests at its at-rest state, which is the right look at the top of a page.
private struct UIKitScrollOffset: UIViewRepresentable {
    var action: (CGFloat) -> Void

    func makeUIView(context: Context) -> ScrollOffsetProbe { ScrollOffsetProbe() }

    func updateUIView(_ view: ScrollOffsetProbe, context: Context) { view.action = action }
}

/// The view behind ``UIKitScrollOffset``.
final class ScrollOffsetProbe: UIView {
    var action: (CGFloat) -> Void = { _ in }
    private var observation: NSKeyValueObservation?
    private var attempts = 0
    private var last: CGFloat?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            observation = nil
            attempts = 0
        } else {
            attach()
        }
    }

    /// Looks for the scroll view; a page whose list is built a moment after it appears gets a few more tries.
    private func attach() {
        guard observation == nil else { return }
        if let scroll = Self.pageScrollView(near: self) {
            #if DEBUG
            NSLog("HeaderEdgeFade: tracking %@ after %d tries", String(describing: type(of: scroll)), attempts)
            #endif
            report(scroll)
            observation = scroll.observe(\.contentOffset, options: [.new]) { [weak self] scroll, _ in
                MainActor.assumeIsolated { self?.report(scroll) }
            }
            return
        }
        attempts += 1
        guard attempts <= 10 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.attach() }
    }

    private func report(_ scroll: UIScrollView) {
        let value = HeaderEdgeFade.trackedOffset(contentOffset: scroll.contentOffset.y, topInset: scroll.adjustedContentInset.top)
        guard value != last else { return }
        last = value
        action(value)
    }

    /// The vertical scroll view that holds the page: the shallowest one, in the nearest ancestor that has one, that is about as
    /// wide as the probe's container. A sideways rail inside the page is narrower or deeper and is passed over.
    static func pageScrollView(near probe: UIView) -> UIScrollView? {
        var ancestor = probe.superview
        for _ in 0..<8 {
            guard let container = ancestor else { return nil }
            var queue = [container]
            var depth = 0
            while !queue.isEmpty, depth < 8 {
                var next: [UIView] = []
                for view in queue {
                    if let scroll = view as? UIScrollView, scroll.bounds.width >= container.bounds.width * 0.8,
                       scroll.contentSize.width <= scroll.bounds.width + 1 {
                        return scroll
                    }
                    next += view.subviews.filter { $0 !== probe }
                }
                queue = next
                depth += 1
            }
            if container.next is UIViewController { return nil }
            ancestor = container.superview
        }
        return nil
    }
}
#endif

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
