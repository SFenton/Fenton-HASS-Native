import SwiftUI
#if os(iOS)
import UIKit
#endif

extension View {
    /// Scrolls this page's main scroll view to its top whenever `token` changes after the page appeared: the second tap on the
    /// selected tab, once its stack is at the root (design: `.agents/design/motion.md` §4.1). The scroll is the system's
    /// animated `setContentOffset`, as UIKit does for a tab bar controller.
    ///
    /// It looks for the vertical scroll view that covers most of the page, so it works for a `ScrollView` and a `List` alike.
    /// - Parameter token: A counter ``ShellNavigator`` bumps per request. Its value at first appearance is not a request.
    func scrollsToTop(whenRequested token: Int) -> some View {
        #if os(iOS)
        background { ScrollToTopBridge(token: token).allowsHitTesting(false) }
        #else
        self
        #endif
    }
}

#if os(iOS)
/// Hosts a zero-size view that finds the page's scroll view when asked.
private struct ScrollToTopBridge: UIViewRepresentable {
    var token: Int

    func makeCoordinator() -> Coordinator { Coordinator(token: token) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        guard context.coordinator.token != token else { return }
        context.coordinator.token = token
        // Next turn: the view must be in its window to be searched from.
        Task { @MainActor in Self.scrollToTop(from: view) }
    }

    final class Coordinator {
        var token: Int
        init(token: Int) { self.token = token }
    }

    @MainActor
    static func scrollToTop(from view: UIView) {
        var responder: UIResponder? = view
        while let current = responder, !(current is UIViewController) { responder = current.next }
        guard let controller = responder as? UIViewController, let window = view.window,
              let scroll = mainScrollView(in: controller.view, window: window) else { return }
        let top = -scroll.adjustedContentInset.top
        guard scroll.contentOffset.y > top + 0.5 else { return }
        scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: top), animated: true)
    }

    /// The visible vertical scroll view with the most area (not a sideways rail, which is wider than tall).
    @MainActor
    static func mainScrollView(in root: UIView, window: UIWindow) -> UIScrollView? {
        var best: (view: UIScrollView, area: CGFloat)?
        var stack: [UIView] = [root]
        while let view = stack.popLast() {
            stack.append(contentsOf: view.subviews)
            guard let scroll = view as? UIScrollView, !scroll.isHidden, scroll.alpha > 0.01 else { continue }
            let visible = scroll.convert(scroll.bounds, to: window).intersection(window.bounds)
            guard visible.width > 200, visible.height > 200,
                  scroll.contentSize.height > scroll.bounds.height + 1 || scroll.alwaysBounceVertical else { continue }
            let area = visible.width * visible.height
            if best == nil || area > best!.area { best = (scroll, area) }
        }
        return best?.view
    }
}
#endif
