import CoreGraphics
@testable import HassDesign
import SwiftUI
import Testing

struct DynamicGridMetricsTests {
    @Test func columnsGrowWithWidthUpToMax() {
        #expect(DynamicGridMetrics(width: 343, minCellWidth: 160, maxColumns: 4, spacing: 12).columns == 2)
        #expect(DynamicGridMetrics(width: 1000, minCellWidth: 160, maxColumns: 4, spacing: 12).columns == 4)
        #expect(DynamicGridMetrics(width: 100, minCellWidth: 160, maxColumns: 4, spacing: 12).columns == 1)
    }

    @Test func leftoverWidthIsSharedEqually() {
        let metrics = DynamicGridMetrics(width: 343, minCellWidth: 160, maxColumns: 4, spacing: 12)
        #expect(metrics.cellWidth == 165.5)
        #expect(metrics.width(span: 2, spacing: 12) == 343)
    }

    @Test func spansWrapAndClamp() {
        let metrics = DynamicGridMetrics(width: 343, minCellWidth: 160, maxColumns: 4, spacing: 12)
        let placements = metrics.placements(spans: [1, 2, 5, 1])
        #expect(placements.map(\.row) == [0, 1, 2, 3])
        #expect(placements.map(\.span) == [1, 2, 2, 1])
        #expect(placements.map(\.column) == [0, 0, 0, 0])
    }

    @Test func incompleteRowStaysLeading() {
        let metrics = DynamicGridMetrics(width: 520, minCellWidth: 160, maxColumns: 4, spacing: 12)
        let placements = metrics.placements(spans: [1, 1, 1, 1])
        #expect(metrics.columns == 3)
        #expect(placements.last?.row == 1)
        #expect(placements.last?.column == 0)
    }

    /// An unbounded size probe (`.infinity`) must not trap converting the column count to `Int`.
    @Test func unboundedWidthUsesEveryColumnAtMinimumWidth() {
        for width in [CGFloat.infinity, .nan] {
            let metrics = DynamicGridMetrics(width: width, minCellWidth: 160, maxColumns: 4, spacing: 12)
            #expect(metrics.columns == 4)
            #expect(metrics.cellWidth == 160)
        }
    }

    @MainActor @Test func unboundedWidthDoesNotTrapInLayout() {
        #expect(DynamicGridMetrics(width: .infinity, minCellWidth: 150, maxColumns: 4, spacing: 12).columns == 4)
        let grid = DynamicGridLayout { ForEach(0..<5, id: \.self) { Text("Tile \($0)") } }
        let probed = HStack { grid.frame(maxWidth: .infinity) }.fixedSize(horizontal: true, vertical: false)
        #expect(ImageRenderer(content: probed).cgImage != nil)
    }
}

/// Equal row heights (Lights sheet, room details): every tile row takes the tallest tile's height; headings keep theirs.
@MainActor
struct DynamicGridEqualHeightTests {
    @Test func equalizedRaisesTileRowsAndKeepsHeadings() {
        #expect(DynamicGridLayout.equalized([20, 88, 120, 20, 96], headerRows: [0, 3]) == [20, 120, 120, 20, 120])
        #expect(DynamicGridLayout.equalized([88, 104], headerRows: []) == [104, 104])
        #expect(DynamicGridLayout.equalized([30], headerRows: [0]) == [30])
        #expect(DynamicGridLayout.equalized([], headerRows: []) == [])
    }

    /// A wrapping title in one row lifts every row; a heading spans the whole width on its own row.
    @Test func gridMeasuresEqualRowsAroundHeadings() {
        let grid = DynamicGridLayout(minCellWidth: 140, maxColumns: 2, spacing: 10, equalRowHeights: true) {
            Color.blue.frame(height: 20).gridHeader()
            Color.red.frame(height: 50)
            Color.red.frame(height: 90)
            Color.red.frame(height: 40)
        }
        // Heading 20, then two tile rows of 90 (the tallest tile), with a 10 gap after each row.
        let height = UIHostingSizing.measure(grid, width: 300)
        #expect(abs(height - (20 + 10 + 90 + 10 + 90)) < 0.5, "measured \(height)")
    }
}

/// Measures a view's height at a width.
@MainActor
enum UIHostingSizing {
    static func measure(_ view: some View, width: CGFloat) -> CGFloat {
        #if canImport(UIKit)
        let controller = UIHostingController(rootView: view)
        return controller.sizeThatFits(in: CGSize(width: width, height: .infinity)).height
        #else
        let controller = NSHostingController(rootView: view)
        return controller.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
        #endif
    }
}
