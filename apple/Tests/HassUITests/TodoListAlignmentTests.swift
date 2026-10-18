import Foundation
@testable import HassUI
import Testing

/// The quick links header lines up with the list's rows by their widths, which do not change as the list scrolls
/// (a position did, and was read for every plain row on every frame).
@MainActor
struct TodoListAlignmentTests {
    @Test func aHeaderIsSetInByHalfTheWidthItLosesOnBothSides() {
        // An iPhone: the margin leaves a row 370 pt; the system sets a header in 16 pt more on each side.
        #expect(TodoRowMetrics.headerInset(rowWidth: 370, headerWidth: 338) == 16)
        #expect(TodoRowMetrics.headerInset(rowWidth: 1100, headerWidth: 1100) == 0)
    }

    @Test func nothingAlignsUntilBothWidthsAreKnownAndNeverGrowsTheHeader() {
        #expect(TodoRowMetrics.headerInset(rowWidth: nil, headerWidth: 338) == 0)
        #expect(TodoRowMetrics.headerInset(rowWidth: 370, headerWidth: nil) == 0)
        // A header wider than the row (a window resize caught between two measurements) is not pulled in.
        #expect(TodoRowMetrics.headerInset(rowWidth: 338, headerWidth: 370) == 0)
    }

    @Test func aRowReportingTheSameWidthAgainWritesNothing() {
        let metrics = TodoRowMetrics()
        #expect(metrics.rowWidth == nil)
        metrics.report(rowWidth: 370)
        #expect(metrics.rowWidth == 370)
        metrics.report(rowWidth: 370)
        #expect(metrics.rowWidth == 370)
        metrics.report(rowWidth: 340)
        #expect(metrics.rowWidth == 340)
    }
}
