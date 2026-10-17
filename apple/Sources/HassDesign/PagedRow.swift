import SwiftUI

/// A horizontally paging row of equal-width cells (the hourly weather). On iOS the paging happens in a UIKit scroll view,
/// so a swipe writes nothing into the surrounding page's SwiftUI view graph (``HostedHorizontalScroll``;
/// `.agents/patterns/status-rail.md`, Scrolling); elsewhere it is a SwiftUI `ScrollView`.
///
/// ``firstVisible`` is the index of the first cell on screen, always the first cell of a page. Writing it moves the row
/// to that page; swiping writes it. It changes once per page, not once per frame, so the page around the row updates
/// only when the page changes.
///
/// VoiceOver reads the cells on the page on screen: the hosted scroll view exposes only the accessibility elements that
/// overlap its viewport, pages with a three-finger swipe (`accessibilityScroll(_:)`) and announces "Page 2 of 3" when it
/// settles. (`accessibilityHidden` on SwiftUI cells does not reach UIKit from a hosted view, so it cannot do this.)
///
/// **Use it for light cells on a long page.** A hosted row pays for its own cells on every frame of a swipe (UIKit moves
/// the hosting view and SwiftUI re-derives its transform, about 0.7 ms a frame for 60 image cards), where a nested
/// SwiftUI `ScrollView` pays for the page around it. The hourly weather (24 text cells on the Weather sheet's long page)
/// fell from 1.1 s to 0.4 to 0.55 s of main-thread time in an 8 s sweep (0.37 s of that is the rain behind it); the Suggested Recipes carousel (60 image cards on a short
/// page) cost the same either way and hitched when a page was built, so it stays a SwiftUI `ScrollView`.
public struct PagedRow<Cell: View>: View {
    private var itemCount: Int
    private var perPage: Int
    private var firstVisible: Binding<Int?>
    private var animatesPaging: Bool
    private var clipsToBounds: Bool
    private var cell: (Int) -> Cell
    /// Bumped when the cells' size changes, so the row's container asks for a new height.
    @State private var sizeChanges = 0
    #if !os(iOS)
    @State private var viewport: CGFloat?
    #endif

    /// Creates a row.
    /// - Parameters:
    ///   - itemCount: Cells in the row.
    ///   - perPage: Cells on each page.
    ///   - firstVisible: The first cell on screen; set it to page the row.
    ///   - animatesPaging: Whether setting ``firstVisible`` scrolls the row across (false with Reduce Motion).
    ///   - clipsToBounds: Whether the row clips to its own width. Unclipped, the next page peeks into the margin beside it.
    ///   - cell: The cell at an index.
    public init(
        itemCount: Int, perPage: Int, firstVisible: Binding<Int?>, animatesPaging: Bool = true, clipsToBounds: Bool = true,
        @ViewBuilder cell: @escaping (Int) -> Cell
    ) {
        self.itemCount = itemCount
        self.perPage = max(1, perPage)
        self.firstVisible = firstVisible
        self.animatesPaging = animatesPaging
        self.clipsToBounds = clipsToBounds
        self.cell = cell
    }

    public var body: some View {
        #if os(iOS)
        let _ = sizeChanges
        HostedHorizontalScroll(
            content: PagedCells(itemCount: itemCount, perPage: perPage, fallbackViewport: nil, cell: cell),
            paging: HostedPaging(
                itemCount: itemCount, perPage: perPage, firstVisible: firstVisible, animated: animatesPaging, clips: clipsToBounds,
                contentSizeChanged: { sizeChanges += 1 }
            )
        )
        #else
        ScrollView(.horizontal, showsIndicators: false) {
            PagedCells(itemCount: itemCount, perPage: perPage, fallbackViewport: viewport, cell: cell)
        }
        .scrollClipDisabled(!clipsToBounds)
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { viewport = $0 }
        #endif
    }
}

/// The cells of a ``PagedRow`` laid in a row, each `viewport / perPage` wide. The hosting scroll view hands the viewport
/// width down through the environment.
private struct PagedCells<Cell: View>: View {
    var itemCount: Int
    var perPage: Int
    var fallbackViewport: CGFloat?
    var cell: (Int) -> Cell
    @Environment(\.hostedViewportWidth) private var hostedViewport
    @Environment(\.hostedRevision) private var revision

    var body: some View {
        let _ = revision
        let width = max(1, (hostedViewport ?? fallbackViewport ?? 0) / CGFloat(perPage))
        HStack(alignment: .top, spacing: 0) {
            ForEach(0..<max(0, itemCount), id: \.self) { index in
                cell(index).frame(width: width)
            }
        }
    }
}

extension EnvironmentValues {
    /// The width of the viewport a ``HostedHorizontalScroll`` shows its content through, for content that sizes itself to
    /// whole pages. `nil` outside a paging hosted scroll view.
    @Entry var hostedViewportWidth: CGFloat?
    /// Changes with every update of a ``HostedHorizontalScroll``, so content built from closures re-runs.
    @Entry var hostedRevision = 0
}
