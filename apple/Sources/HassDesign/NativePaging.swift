import SwiftUI
#if os(iOS)
import UIKit
#endif

public extension View {
    /// Makes the horizontal `ScrollView` this content sits in page one viewport at a time, without
    /// `scrollTargetBehavior`.
    ///
    /// **Why not `scrollTargetBehavior(.paging)`.** On iOS 27.0 every `ScrollBehaviorModifier` allocates a fresh
    /// `ScrollEnvironmentStorage` each time the environment above it changes, and the observation state of the
    /// old one is never released. The scene phase is in the environment, so the app leaked about 14 objects per
    /// paged carousel on every background and foreground (heap census, 2026-10-16) and a fixed
    /// scroll took 3 to 4% more CPU after 30 to 60 resumes (simulator), and removing the modifier flattened it
    /// (`.agents/patterns/resume-lifecycle.md`). `ScrollView` is a `UIScrollView` on iOS, and `isPagingEnabled` is
    /// the paging that modifier asked for; where no scroll view is found the row scrolls freely.
    ///
    /// Put it on the content *inside* the scroll view, and keep `scrollPosition(id:)` for the page the row is on.
    /// Cells must be a whole fraction of the viewport wide (`containerRelativeFrame(count:)`) so pages line up.
    func pagesScrollViewByViewport() -> some View {
        #if os(iOS)
        background { ViewportPagingEnabler().allowsHitTesting(false).accessibilityHidden(true) }
        #else
        self
        #endif
    }
}

#if os(iOS)
/// An invisible view that turns paging on for the `UIScrollView` it lives in.
private struct ViewportPagingEnabler: UIViewRepresentable {
    func makeUIView(context: Context) -> EnablerView { EnablerView() }
    func updateUIView(_ view: EnablerView, context: Context) { view.enable() }

    final class EnablerView: UIView {
        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            isAccessibilityElement = false
        }

        required init?(coder: NSCoder) { nil }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            enable()
        }

        /// The nearest enclosing scroll view, if SwiftUI has built it yet.
        func enable() {
            var ancestor = superview
            while let view = ancestor {
                if let scrollView = view as? UIScrollView {
                    if !scrollView.isPagingEnabled { scrollView.isPagingEnabled = true }
                    return
                }
                ancestor = view.superview
            }
        }
    }
}
#endif
