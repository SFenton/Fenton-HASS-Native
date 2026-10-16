import SwiftUI

/// Pure column math for ``DynamicGridLayout``, separated so it can be unit tested.
public struct DynamicGridMetrics: Equatable, Sendable {
    /// Number of tracks.
    public var columns: Int
    /// Width of one track.
    public var cellWidth: CGFloat

    /// Computes tracks for a width.
    ///
    /// Columns are `floor((width + spacing) / (minCellWidth + spacing))`, clamped to `1...maxColumns`;
    /// leftover width is shared equally (web `dynamicGridLayout.ts`).
    /// A non-finite width (an unbounded `.infinity` size probe) gets every column at the minimum width.
    ///
    /// With `evenColumns` (a window with a hinge, the unfolded iPhone Duo) a count of two or more rounds down to
    /// an even number (``evenRounded(_:)``), so the fold falls between tracks rather than through a tile; a single
    /// track stays single.
    public init(width: CGFloat, minCellWidth: CGFloat, maxColumns: Int, spacing: CGFloat, evenColumns: Bool = false) {
        guard width.isFinite else {
            columns = max(maxColumns, 1)
            cellWidth = minCellWidth
            return
        }
        let fit = Int(((width + spacing) / (minCellWidth + spacing)).rounded(.down))
        var columns = min(max(fit, 1), max(maxColumns, 1))
        if evenColumns { columns = Self.evenRounded(columns) }
        self.columns = columns
        self.cellWidth = max(0, (width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
    }

    /// The count rounded down to an even number, never below two: 5 becomes 4, 3 becomes 2. One track (a window
    /// too narrow for two) stays one. Hinge-aware grids use it (`.agents/patterns/dynamic-grid.md`).
    public static func evenRounded(_ columns: Int) -> Int {
        guard columns >= 2 else { return max(columns, 1) }
        return columns - columns % 2
    }

    /// Width of an item spanning `span` tracks (clamped to the track count).
    public func width(span: Int, spacing: CGFloat) -> CGFloat {
        let span = min(max(span, 1), columns)
        return cellWidth * CGFloat(span) + spacing * CGFloat(span - 1)
    }

    /// Row/column placement for items with the given spans. Rows fill left to right; an item that does
    /// not fit on the current row starts the next. Incomplete rows stay leading-aligned.
    public func placements(spans: [Int]) -> [(row: Int, column: Int, span: Int)] {
        var row = 0
        var column = 0
        return spans.map { requested in
            let span = min(max(requested, 1), columns)
            if column + span > columns {
                row += 1
                column = 0
            }
            defer { column += span }
            return (row, column, span)
        }
    }
}

/// How many tracks a child of ``DynamicGridLayout`` claims.
public struct GridSpanKey: LayoutValueKey {
    public static let defaultValue = 1
}

/// Marks a full-width heading row in a ``DynamicGridLayout``; equal row heights skip it.
public struct GridHeaderKey: LayoutValueKey {
    public static let defaultValue = false
}

public extension View {
    /// Claims `span` tracks in a ``DynamicGridLayout``.
    func gridSpan(_ span: Int) -> some View { layoutValue(key: GridSpanKey.self, value: span) }

    /// Makes this child a heading that takes a whole row of a ``DynamicGridLayout`` (a section title between runs
    /// of tiles), so one grid can hold several sections whose tiles share one height.
    func gridHeader() -> some View {
        layoutValue(key: GridSpanKey.self, value: Int.max).layoutValue(key: GridHeaderKey.self, value: true)
    }
}

/// The shared responsive grid (pattern: `.agents/patterns/dynamic-grid.md`).
public struct DynamicGridLayout: Layout {
    public var minCellWidth: CGFloat
    public var maxColumns: Int
    public var spacing: CGFloat
    /// Gives every tile row the height of the tallest tile in the grid, so a title that wraps to two lines (Master
    /// Bedroom Closet on an iPhone) lifts every tile to match. Heading rows (``View/gridHeader()``) keep their own
    /// height. Measured on every layout pass, so it follows Dynamic Type and rotation. Tiles fill the height they
    /// are offered inside ``View/equalHeightTiles()``.
    public var equalRowHeights: Bool
    /// Rounds the column count down to an even number (``DynamicGridMetrics/evenRounded(_:)``). Set for you from the
    /// environment: grids called as `DynamicGridLayout(...) { }` turn it on while ``SwiftUICore/EnvironmentValues/windowHinge``
    /// is set (the unfolded iPhone Duo), so no tile straddles the fold.
    public var evenColumns = false

    /// Creates a grid.
    public init(minCellWidth: CGFloat = 150, maxColumns: Int = 4, spacing: CGFloat = HassTokens.Spacing.m,
                equalRowHeights: Bool = false) {
        self.minCellWidth = minCellWidth
        self.maxColumns = maxColumns
        self.spacing = spacing
        self.equalRowHeights = equalRowHeights
    }

    /// Calls the grid as a view, reading the window's hinge so the column count rounds to an even number across a
    /// fold. A `Layout` cannot read the environment itself, so the call goes through a small wrapper view.
    @MainActor
    public func callAsFunction<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HingeAwareGrid(layout: self, content: content())
    }

    /// Row heights measured per width during one layout pass. Scroll views and stacks propose the same width
    /// several times per pass, and nested grids multiply that; measuring every tile once per width instead of
    /// once per call cut layout work on room pages (`.agents/patterns/dynamic-grid.md`).
    public struct Cache {
        var rows: [CGFloat: [CGFloat]] = [:]
    }

    public func makeCache(subviews: Subviews) -> Cache { Cache() }

    /// Any change to the subviews (or their content) invalidates every measurement.
    public func updateCache(_ cache: inout Cache, subviews: Subviews) { cache.rows.removeAll(keepingCapacity: true) }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        // Unspecified or unbounded (`.infinity`, e.g. a hosting view's maximum-size probe): the ideal width.
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? minCellWidth * CGFloat(maxColumns)
        let rows = rowHeights(width: width, subviews: subviews, cache: &cache)
        let height = rows.reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let metrics = DynamicGridMetrics(width: bounds.width, minCellWidth: minCellWidth, maxColumns: maxColumns, spacing: spacing,
                                         evenColumns: evenColumns)
        let rows = rowHeights(width: bounds.width, subviews: subviews, cache: &cache)
        let placements = metrics.placements(spans: subviews.map { $0[GridSpanKey.self] })
        var rowTops: [CGFloat] = []
        var y = bounds.minY
        for height in rows {
            rowTops.append(y)
            y += height + spacing
        }
        for (index, subview) in subviews.enumerated() {
            let place = placements[index]
            let x = bounds.minX + CGFloat(place.column) * (metrics.cellWidth + spacing)
            let width = metrics.width(span: place.span, spacing: spacing)
            subview.place(
                at: CGPoint(x: x, y: rowTops[place.row]),
                proposal: ProposedViewSize(width: width, height: rows[place.row])
            )
        }
    }

    private func rowHeights(width: CGFloat, subviews: Subviews, cache: inout Cache) -> [CGFloat] {
        if let rows = cache.rows[width] { return rows }
        let rows = measureRows(width: width, subviews: subviews)
        cache.rows[width] = rows
        return rows
    }

    private func measureRows(width: CGFloat, subviews: Subviews) -> [CGFloat] {
        let metrics = DynamicGridMetrics(width: width, minCellWidth: minCellWidth, maxColumns: maxColumns, spacing: spacing,
                                         evenColumns: evenColumns)
        let placements = metrics.placements(spans: subviews.map { $0[GridSpanKey.self] })
        var heights: [CGFloat] = []
        var headerRows = Set<Int>()
        for (index, subview) in subviews.enumerated() {
            let place = placements[index]
            let size = subview.sizeThatFits(ProposedViewSize(width: metrics.width(span: place.span, spacing: spacing), height: nil))
            if place.row >= heights.count { heights.append(0) }
            heights[place.row] = max(heights[place.row], size.height)
            if subview[GridHeaderKey.self] { headerRows.insert(place.row) }
        }
        return equalRowHeights ? Self.equalized(heights, headerRows: headerRows) : heights
    }

    /// Raises every non-heading row to the tallest non-heading row.
    static func equalized(_ heights: [CGFloat], headerRows: Set<Int>) -> [CGFloat] {
        let tallest = heights.indices.filter { !headerRows.contains($0) }.map { heights[$0] }.max() ?? 0
        return heights.indices.map { headerRows.contains($0) ? heights[$0] : tallest }
    }
}

/// Applies the window's hinge to a ``DynamicGridLayout`` (see ``DynamicGridLayout/callAsFunction(_:)``).
private struct HingeAwareGrid<Content: View>: View {
    var layout: DynamicGridLayout
    var content: Content
    @Environment(\.windowHinge) private var hinge

    var body: some View {
        var layout = layout
        layout.evenColumns = layout.evenColumns || hinge != nil
        return AnyLayout(layout) { content }
    }
}
