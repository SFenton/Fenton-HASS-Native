@testable import HassDesign
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
}
