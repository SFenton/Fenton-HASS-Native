import CoreGraphics
@testable import HassDesign
import Testing

struct ChipRailTests {
    @Test func chipsScrollInCompactWidthAndWrapInRegularWidth() {
        #expect(ChipRailMode.resolve(isRegularWidth: false) == .scroll)
        #expect(ChipRailMode.resolve(isRegularWidth: true) == .wrap)
    }

    /// Unfolded Duo, landscape: the hinge band is 455.3 to 495.7 pt (measured on the simulator, 951 pt wide).
    private let hinge = CGRect(x: 455.3, y: 0, width: 40.4, height: 669)

    @Test func railStopsTwentyFourPointsShortOfTheHinge() {
        let rail = CGRect(x: 0, y: 100, width: 868, height: 60)
        #expect(abs(ChipRailMetrics.trailingInset(railFrame: rail, hinge: hinge) - (868 - (455.3 - 24))) < 0.001)
    }

    @Test func aMeasuredInsetOnlyAppliesWhileThereIsAHinge() {
        #expect(ChipRailMetrics.appliedInset(measured: 120, hinge: hinge) == 120)
        // A fold that closed stops measuring, so the last value must not linger.
        #expect(ChipRailMetrics.appliedInset(measured: 120, hinge: nil) == 0)
        #expect(ChipRailMetrics.appliedInset(measured: 0, hinge: hinge) == 0)
    }

    @Test func hostedRowFillsTheScrollViewAndScrollsWhenWider() {
        let bounds = CGSize(width: 402, height: 64)
        // Six chips are wider than the phone: the content scrolls.
        #expect(ChipRailMetrics.hostedContentSize(natural: CGSize(width: 910, height: 64), bounds: bounds) == CGSize(width: 910, height: 64))
        // Two chips fit: the content is exactly the scroll view, so nothing scrolls and no bounce range appears.
        #expect(ChipRailMetrics.hostedContentSize(natural: CGSize(width: 300, height: 64), bounds: bounds) == bounds)
        // The height follows the scroll view, never the natural size, so it cannot scroll sideways-and-up.
        #expect(ChipRailMetrics.hostedContentSize(natural: CGSize(width: 910, height: 90), bounds: bounds).height == 64)
    }

    @Test func noInsetWithoutAHingeOrWhenTheRailDoesNotReachIt() {
        let rail = CGRect(x: 0, y: 100, width: 868, height: 60)
        #expect(ChipRailMetrics.trailingInset(railFrame: rail, hinge: nil) == 0)
        // A rail in the leading half already ends before the gap.
        #expect(ChipRailMetrics.trailingInset(railFrame: CGRect(x: 0, y: 0, width: 400, height: 60), hinge: hinge) == 0)
        // A rail in the trailing half starts past the hinge.
        #expect(ChipRailMetrics.trailingInset(railFrame: CGRect(x: 500, y: 0, width: 368, height: 60), hinge: hinge) == 0)
        // A horizontal fold (wider than tall) is not a vertical division.
        #expect(ChipRailMetrics.trailingInset(railFrame: rail, hinge: CGRect(x: 0, y: 300, width: 868, height: 20)) == 0)
    }
}
