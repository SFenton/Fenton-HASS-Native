#if os(iOS)
import SwiftUI
import UIKit

/// A sideways-scrolling row whose scrolling happens in UIKit, so dragging it writes nothing into the page's SwiftUI
/// view graph (`.agents/patterns/status-rail.md`, Scrolling).
///
/// A SwiftUI `ScrollView` nested in a page's vertical `ScrollView` commits its offset through the page's view graph on
/// every frame of a drag, and that dirty-propagation work grows with the page around it (measured 2026-10-16: about
/// 0.5 ms of main-thread time per frame on a 120-tile page, none left with this view). A `UIScrollView` moves the same
/// pixels on the render server with no graph work. The content stays ordinary SwiftUI, hosted once and handed the
/// surrounding environment, so chips keep reading the entity store and updating in place.
struct HostedHorizontalScroll<Content: View>: UIViewRepresentable {
    var content: Content
    @Environment(\.self) private var environment

    func makeUIView(context: Context) -> HostedScrollView<Content> {
        HostedScrollView(rootView: root)
    }

    func updateUIView(_ view: HostedScrollView<Content>, context: Context) {
        view.update(root)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView view: HostedScrollView<Content>, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? view.naturalSize.width, height: view.naturalSize.height)
    }

    private var root: HostedRoot<Content> { HostedRoot(content: content, environment: environment) }
}

/// The hosted content, re-rooted in the page's environment (a hosting controller starts from a blank one).
struct HostedRoot<Content: View>: View {
    var content: Content
    var environment: EnvironmentValues
    /// Called with the content's natural size whenever it changes.
    var onNaturalSize: (CGSize) -> Void = { _ in }

    var body: some View {
        content
            .fixedSize()
            .onGeometryChange(for: CGSize.self) { $0.size } action: { onNaturalSize($0) }
            .transformEnvironment(\.self) { hosted in
                // Keep the hosting view's own accessibility switch: the copy was taken from the page when it last
                // updated, which can be before an assistive technology (or XCUITest) connected, and a stale `false`
                // left the chips out of the accessibility tree entirely (iPhone and Duo journeys, 2026-10-16).
                let accessibilityEnabled = hosted.accessibilityEnabled
                hosted = environment
                hosted.accessibilityEnabled = accessibilityEnabled
            }
    }
}

/// The `UIScrollView` behind ``HostedHorizontalScroll``.
final class HostedScrollView<Content: View>: UIScrollView {
    private let host: UIHostingController<HostedRoot<Content>>

    init(rootView: HostedRoot<Content>) {
        host = UIHostingController(rootView: rootView)
        super.init(frame: .zero)
        host.safeAreaRegions = []
        host.view.backgroundColor = .clear
        backgroundColor = .clear
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        alwaysBounceHorizontal = true
        alwaysBounceVertical = false
        isDirectionalLockEnabled = true
        contentInsetAdjustmentBehavior = .never
        clipsToBounds = true
        addSubview(host.view)
        host.rootView = withResizeHandler(rootView)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    /// The content's natural size: how wide the row is and how tall the scroll view should be.
    var naturalSize: CGSize {
        host.view.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
    }

    func update(_ rootView: HostedRoot<Content>) {
        host.rootView = withResizeHandler(rootView)
        setNeedsLayout()
    }

    private func withResizeHandler(_ rootView: HostedRoot<Content>) -> HostedRoot<Content> {
        var rootView = rootView
        rootView.onNaturalSize = { [weak self] _ in self?.setNeedsLayout() }
        return rootView
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = ChipRailMetrics.hostedContentSize(natural: naturalSize, bounds: bounds.size)
        if host.view.frame.size != size { host.view.frame = CGRect(origin: .zero, size: size) }
        if contentSize != size { contentSize = size }
    }

    /// Joins the nearest view controller so the hosted content gets appearance and trait callbacks.
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            guard host.parent != nil else { return }
            host.willMove(toParent: nil)
            host.removeFromParent()
            return
        }
        guard host.parent == nil else { return }
        var responder: UIResponder? = self
        while let next = responder?.next, !(next is UIViewController) { responder = next }
        guard let parent = responder?.next as? UIViewController else { return }
        parent.addChild(host)
        host.didMove(toParent: parent)
    }
}
#endif
