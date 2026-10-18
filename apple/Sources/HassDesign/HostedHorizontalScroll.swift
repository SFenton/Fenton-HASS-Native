#if os(iOS)
import SwiftUI
import UIKit

/// How a ``HostedHorizontalScroll`` pages: the cells on a page, and the first cell on screen (see ``PagedRow``).
struct HostedPaging {
    var itemCount: Int
    var perPage: Int
    /// The first cell on screen, always a page's first cell. Read to follow the page, written as the page changes.
    var firstVisible: Binding<Int?>
    /// Whether moving to a page written into ``firstVisible`` scrolls across to it.
    var animated: Bool
    /// Whether the scroll view clips to its bounds; unclipped, the next page peeks into the margin beside it.
    var clips: Bool
    /// Called when the content's size changed after layout, so the row asks its container for a new height.
    var contentSizeChanged: () -> Void = {}

    var pageCount: Int { PagedRowMetrics.pageCount(itemCount: itemCount, perPage: perPage) }
}

/// A sideways-scrolling row whose scrolling happens in UIKit, so dragging it writes nothing into the page's SwiftUI
/// view graph (`.agents/patterns/status-rail.md`, Scrolling).
///
/// A SwiftUI `ScrollView` nested in a page's vertical `ScrollView` commits its offset through the page's view graph on
/// every frame of a drag, and that dirty-propagation work grows with the page around it (measured 2026-10-16: about
/// 0.5 ms of main-thread time per frame on a 120-tile page, none left with this view). A `UIScrollView` moves the same
/// pixels on the render server with no graph work. The content stays ordinary SwiftUI, hosted once and handed the
/// surrounding environment, so chips keep reading the entity store and updating in place.
///
/// With ``HostedPaging`` the scroll view pages by its own width and reports the page it settles on; the content reads the
/// viewport width from the environment to size its cells (``PagedRow``).
struct HostedHorizontalScroll<Content: View>: UIViewRepresentable {
    var content: Content
    var paging: HostedPaging?
    @Environment(\.self) private var environment

    func makeUIView(context: Context) -> HostedScrollView<Content> {
        let view = HostedScrollView(rootView: root(viewportWidth: nil))
        view.apply(paging: paging)
        return view
    }

    func updateUIView(_ view: HostedScrollView<Content>, context: Context) {
        view.apply(paging: paging)
        view.update(root(viewportWidth: view.viewportWidth))
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView view: HostedScrollView<Content>, context: Context) -> CGSize? {
        if paging != nil, let width = proposal.width {
            // The cells are as wide as the viewport, so the content's height is known only for the proposed width.
            view.apply(paging: paging)
            if view.viewportWidth != width { view.update(root(viewportWidth: width)) }
        }
        return CGSize(width: proposal.width ?? view.naturalSize.width, height: view.naturalSize.height)
    }

    private func root(viewportWidth: CGFloat?) -> HostedRoot<Content> {
        HostedRoot(content: content, environment: environment, viewportWidth: paging == nil ? nil : viewportWidth)
    }
}

/// The hosted content, re-rooted in the page's environment (a hosting controller starts from a blank one).
struct HostedRoot<Content: View>: View {
    var content: Content
    var environment: EnvironmentValues
    /// The viewport the content pages in, for a paging scroll view.
    var viewportWidth: CGFloat?
    /// Counts the updates the representable received. Content built from a closure (``PagedRow``) cannot be compared, and a
    /// closure with new captures can compare equal to the old one, so the cells' body was skipped and kept stale values
    /// (the off-page hours stayed in the accessibility tree on iPad); the revision reaches them through the environment.
    var revision = 0
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
                hosted.hostedViewportWidth = viewportWidth
                hosted.hostedRevision = revision
            }
    }
}

/// The `UIScrollView` behind ``HostedHorizontalScroll``.
final class HostedScrollView<Content: View>: UIScrollView, UIScrollViewDelegate {
    private let host: UIHostingController<HostedRoot<Content>>
    private var paging: HostedPaging?
    /// True while a move to a page written into the binding is under way, so the offsets it passes through are not
    /// reported back as pages the user chose.
    private var isMovingToPage = false
    /// The viewport width the hosted content was last built for (paging only).
    private(set) var viewportWidth: CGFloat?

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
    ///
    /// A paging row keeps the last size, because measuring the whole hosted row (every page of cards) took almost half
    /// of the busiest turns when a page change re-laid out the row's container, and again on every frame of a swipe
    /// (`layoutSubviews`). The hosted content reports its size when it changes (``HostedRoot/onNaturalSize``), which
    /// replaces the kept one; a new viewport width drops it.
    var naturalSize: CGSize {
        if paging != nil, let measuredSize { return measuredSize }
        let size = host.view.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        if paging != nil { measuredSize = size }
        return size
    }

    /// The natural size of a paging row, until the viewport changes or the content reports another.
    private var measuredSize: CGSize?
    private var revision = 0

    /// Takes the paging configuration (or `nil` for a plain scrolling row).
    func apply(paging: HostedPaging?) {
        self.paging = paging
        isPagingEnabled = paging != nil
        delegate = paging == nil ? nil : self
        clipsToBounds = paging?.clips ?? true
        if paging == nil { viewportWidth = nil }
    }

    func update(_ rootView: HostedRoot<Content>) {
        var rootView = rootView
        revision &+= 1
        rootView.revision = revision
        if viewportWidth != rootView.viewportWidth { measuredSize = nil }
        viewportWidth = rootView.viewportWidth
        host.rootView = withResizeHandler(rootView)
        setNeedsLayout()
        followBinding()
    }

    private func withResizeHandler(_ rootView: HostedRoot<Content>) -> HostedRoot<Content> {
        var rootView = rootView
        rootView.onNaturalSize = { [weak self] size in
            guard let self else { return }
            if paging != nil, measuredSize != size {
                let hadSize = measuredSize != nil
                measuredSize = size
                if hadSize { paging?.contentSizeChanged() }
            }
            setNeedsLayout()
        }
        return rootView
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if paging != nil, bounds.width > 0, viewportWidth != bounds.width {
            // A rotation or a split changed the viewport: rebuild the cells for it before measuring them.
            viewportWidth = bounds.width
            measuredSize = nil
            var rootView = host.rootView
            rootView.viewportWidth = bounds.width
            host.rootView = rootView
        }
        let natural = naturalSize
        let rightToLeft = effectiveUserInterfaceLayoutDirection == .rightToLeft
        let size = ChipRailMetrics.hostedContentSize(natural: natural, bounds: bounds.size)
        // The hosted view is as wide as the row, not the scroll view: a wider hosting view centres what it hosts, and a
        // short row (Security's two chips) must start at the leading edge, not mid-page.
        let frame = paging == nil
            ? ChipRailMetrics.hostedContentFrame(natural: natural, bounds: bounds.size, isRightToLeft: rightToLeft)
            : CGRect(origin: .zero, size: size)
        if host.view.frame != frame { host.view.frame = frame }
        if contentSize != size {
            contentSize = size
            if paging == nil, rightToLeft, !isTracking, !isDecelerating {
                // Right to left the row starts at the right: show its leading end, not the scroll view's origin.
                contentOffset.x = ChipRailMetrics.hostedLeadingOffset(contentWidth: size.width, boundsWidth: bounds.width, isRightToLeft: true)
            }
            followBinding()
        }
    }

    // MARK: - Paging

    /// Moves to the page the binding names when it is not the page on screen.
    private func followBinding() {
        guard let paging, bounds.width > 0, contentSize.width > 0, !isTracking, !isDecelerating, !isMovingToPage else { return }
        let pageCount = paging.pageCount
        let wanted = PagedRowMetrics.page(containing: paging.firstVisible.wrappedValue, perPage: paging.perPage, pageCount: pageCount)
        guard wanted != shownPage(paging) else { return }
        let target = CGPoint(x: PagedRowMetrics.offset(ofPage: wanted, viewport: bounds.width, contentWidth: contentSize.width), y: 0)
        isMovingToPage = true
        setContentOffset(target, animated: paging.animated && window != nil)
        if !(paging.animated && window != nil) { isMovingToPage = false }
    }

    private func shownPage(_ paging: HostedPaging) -> Int {
        PagedRowMetrics.page(forOffset: contentOffset.x, viewport: bounds.width, contentWidth: contentSize.width, pageCount: paging.pageCount)
    }

    /// Writes the page on screen into the binding, once per page.
    private func reportPage() {
        guard let paging, bounds.width > 0, !isMovingToPage else { return }
        let first = PagedRowMetrics.firstIndex(ofPage: shownPage(paging), itemCount: paging.itemCount, perPage: paging.perPage)
        if paging.firstVisible.wrappedValue != first { paging.firstVisible.wrappedValue = first }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) { reportPage() }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { isMovingToPage = false }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { announcePage() }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { announcePage() }
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        isMovingToPage = false
        // A page written into the binding while this move was under way is followed now; otherwise the page reached is
        // reported.
        followBinding()
        if !isMovingToPage {
            reportPage()
            announcePage()
        }
    }

    // MARK: - Accessibility

    /// What VoiceOver reads: only the cells on the page on screen. SwiftUI's `accessibilityHidden` on the other pages' cells
    /// does not reach UIKit from a hosted view (XCUITest still listed all 24 hours on iPad), so the scroll view filters the
    /// hosted elements by where they are. VoiceOver pages with ``accessibilityScroll(_:)`` and the controls around the row.
    override var accessibilityElements: [Any]? {
        get {
            guard paging != nil else { return super.accessibilityElements }
            let elements = Self.leafElements(of: host.view)
            let viewport = UIAccessibility.convertToScreenCoordinates(bounds, in: self)
            let frames = elements.map { ($0 as? NSObject)?.accessibilityFrame ?? .null }
            return PagedRowMetrics.indexes(ofFrames: frames, overlapping: viewport).map { elements[$0] }
        }
        set { super.accessibilityElements = newValue }
    }

    /// The accessibility elements under a view, containers flattened.
    private static func leafElements(of container: NSObject) -> [Any] {
        var children: [Any] = container.accessibilityElements ?? []
        if children.isEmpty {
            let count = container.accessibilityElementCount()
            if count != NSNotFound, count > 0 { children = (0..<count).compactMap { container.accessibilityElement(at: $0) } }
        }
        return children.flatMap { child -> [Any] in
            guard let object = child as? NSObject, !object.isAccessibilityElement else { return [child] }
            let nested = leafElements(of: object)
            return nested.isEmpty ? [child] : nested
        }
    }

    /// A three-finger swipe moves by a page, as a paging scroll view does, and says which page it reached.
    override func accessibilityScroll(_ direction: UIAccessibilityScrollDirection) -> Bool {
        guard let paging else { return super.accessibilityScroll(direction) }
        let step: Int
        switch direction {
        case .left, .next: step = 1
        case .right, .previous: step = -1
        default: return super.accessibilityScroll(direction)
        }
        guard let target = PagedRowMetrics.page(from: shownPage(paging), step: step, pageCount: paging.pageCount) else { return false }
        isMovingToPage = true
        setContentOffset(CGPoint(x: PagedRowMetrics.offset(ofPage: target, viewport: bounds.width, contentWidth: contentSize.width), y: 0), animated: true)
        return true
    }

    /// Tells VoiceOver which page the row settled on ("Page 2 of 3"), once per page.
    private func announcePage() {
        guard let paging, bounds.width > 0 else { return }
        let page = shownPage(paging)
        defer { announcedPage = page }
        guard let announcedPage, announcedPage != page, UIAccessibility.isVoiceOverRunning else { return }
        UIAccessibility.post(notification: .pageScrolled, argument: PagedRowMetrics.pageDescription(page, pageCount: paging.pageCount))
    }

    private var announcedPage: Int? = 0

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
