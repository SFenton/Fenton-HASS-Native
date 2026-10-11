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
    public init(width: CGFloat, minCellWidth: CGFloat, maxColumns: Int, spacing: CGFloat) {
        // An unbounded width (a flexible stack's probe) fits every column rather than trapping on Int(.infinity).
        let ratio = ((width + spacing) / (minCellWidth + spacing)).rounded(.down)
        let fit = ratio.isFinite ? Int(ratio) : maxColumns
        let columns = min(max(fit, 1), max(maxColumns, 1))
        self.columns = columns
        self.cellWidth = max(0, (width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
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

public extension View {
    /// Claims `span` tracks in a ``DynamicGridLayout``.
    func gridSpan(_ span: Int) -> some View { layoutValue(key: GridSpanKey.self, value: span) }
}

/// The shared responsive grid (pattern: `.agents/patterns/dynamic-grid.md`).
public struct DynamicGridLayout: Layout {
    public var minCellWidth: CGFloat
    public var maxColumns: Int
    public var spacing: CGFloat

    /// Creates a grid.
    public init(minCellWidth: CGFloat = 150, maxColumns: Int = 4, spacing: CGFloat = HassTokens.Spacing.m) {
        self.minCellWidth = minCellWidth
        self.maxColumns = maxColumns
        self.spacing = spacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // nil or infinite proposals (e.g. an HStack probing a `maxWidth: .infinity` child) get the ideal width.
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? minCellWidth * CGFloat(maxColumns)
        let rows = rowHeights(width: width, subviews: subviews)
        let height = rows.reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let metrics = DynamicGridMetrics(width: bounds.width, minCellWidth: minCellWidth, maxColumns: maxColumns, spacing: spacing)
        let rows = rowHeights(width: bounds.width, subviews: subviews)
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

    private func rowHeights(width: CGFloat, subviews: Subviews) -> [CGFloat] {
        let metrics = DynamicGridMetrics(width: width, minCellWidth: minCellWidth, maxColumns: maxColumns, spacing: spacing)
        let placements = metrics.placements(spans: subviews.map { $0[GridSpanKey.self] })
        var heights: [CGFloat] = []
        for (index, subview) in subviews.enumerated() {
            let place = placements[index]
            let size = subview.sizeThatFits(ProposedViewSize(width: metrics.width(span: place.span, spacing: spacing), height: nil))
            if place.row >= heights.count { heights.append(0) }
            heights[place.row] = max(heights[place.row], size.height)
        }
        return heights
    }
}
