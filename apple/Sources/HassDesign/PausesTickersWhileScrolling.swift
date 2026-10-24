import SwiftUI

public extension EnvironmentValues {
    /// Whether the page the view is on is being scrolled; a ticker holds still meanwhile (`.agents/design/motion.md` §9.10).
    /// Set by ``SwiftUICore/View/pausesTickersWhileScrolling()``.
    @Entry var pageIsScrolling = false
    /// Whether the view's section is on screen; a ticker holds still behind another tab. True outside the shell.
    @Entry var tickerIsOnScreen = true
}

public extension View {
    /// Tells the tickers inside this scroll view when it is moving, so they pause (iOS 18 and later; on iOS 17 they keep going).
    func pausesTickersWhileScrolling() -> some View { modifier(PausesTickersWhileScrolling()) }
}

private struct PausesTickersWhileScrolling: ViewModifier {
    @State private var scrolling = false

    func body(content: Content) -> some View {
        if #available(iOS 18, macOS 15, *) {
            content
                .onScrollPhaseChange { _, phase in scrolling = phase != .idle }
                .environment(\.pageIsScrolling, scrolling)
        } else {
            content
        }
    }
}
