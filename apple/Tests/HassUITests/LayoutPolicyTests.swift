import CoreGraphics
@testable import HassUI
import Testing

struct SplitPolicyTests {
    // Window sizes in points.
    let iPhonePortrait = CGSize(width: 402, height: 874)
    let duoOuter = CGSize(width: 466, height: 678)
    let duoOuterLandscape = CGSize(width: 678, height: 466)
    let duoInnerLandscape = CGSize(width: 951, height: 669)
    let duoInnerPortrait = CGSize(width: 669, height: 951)
    let iPadPortrait = CGSize(width: 834, height: 1210)
    let iPadLandscape = CGSize(width: 1210, height: 834)

    @Test func splitsOnlyInRegularLandscape() {
        #expect(!SplitPolicy.allowsSplit(size: iPhonePortrait, isRegularWidth: false))
        #expect(!SplitPolicy.allowsSplit(size: duoOuter, isRegularWidth: false))
        #expect(!SplitPolicy.allowsSplit(size: duoOuterLandscape, isRegularWidth: false))
        #expect(!SplitPolicy.allowsSplit(size: duoInnerPortrait, isRegularWidth: true))
        #expect(!SplitPolicy.allowsSplit(size: iPadPortrait, isRegularWidth: true))
        #expect(SplitPolicy.allowsSplit(size: duoInnerLandscape, isRegularWidth: true))
        #expect(SplitPolicy.allowsSplit(size: iPadLandscape, isRegularWidth: true))
    }

    @Test func narrowLandscapeWindowsDoNotSplit() {
        #expect(!SplitPolicy.allowsSplit(size: CGSize(width: 700, height: 500), isRegularWidth: true))
    }

    @Test func dividerFollowsHingeElseMidpoint() {
        #expect(SplitPolicy.dividerX(width: 951, hingeMidX: 470) == 470)
        #expect(SplitPolicy.dividerX(width: 1210, hingeMidX: nil) == 605)
        #expect(SplitPolicy.dividerX(width: 1210, hingeMidX: 2000) == 605)
    }
}

@MainActor
struct OrientationPolicyTests {
    @Test func iPhoneIsPortraitOnlyAndIPadAllowsAll() {
        let info: [String: Any] = [
            "UISupportedInterfaceOrientations~iphone": ["UIInterfaceOrientationPortrait"],
            "UISupportedInterfaceOrientations~ipad": [
                "UIInterfaceOrientationPortrait", "UIInterfaceOrientationPortraitUpsideDown",
                "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight",
            ],
        ]
        let phone = OrientationPolicy.declared(in: info, isPad: false)
        #expect(OrientationPolicy.supported(declared: phone, hasHinge: false) == .portrait)
        #expect(OrientationPolicy.supported(declared: phone, hasHinge: true) == .all)
        #expect(OrientationPolicy.supported(declared: OrientationPolicy.declared(in: info, isPad: true), hasHinge: false) == .all)
        #expect(OrientationPolicy.supported(declared: [], hasHinge: false) == .portrait)
    }

    @Test func hingePresenceLatchesOnce() {
        var calls = 0
        let presence = HingePresence { calls += 1 }
        presence.record(hinge: nil)
        #expect(!presence.hasHinge)
        presence.record(hinge: .closed)
        presence.record(hinge: .fullyOpen)
        presence.record(hinge: nil, hasVerticalBar: true)
        #expect(presence.hasHinge)
        #expect(calls == 1)
    }
}

/// Home's two columns on the hinge (plan Phase 4, decision 5).
struct HomeColumnsTests {
    /// Unfolded Duo landscape as measured on the simulator: 951 pt wide, hinge band 455.3 to 495.7 pt, content ending at
    /// the system's trailing bar (868 pt).
    let hinge = CGRect(x: 455.3, y: 0, width: 40.4, height: 669)
    let duoContent = CGRect(x: 0, y: 0, width: 868, height: 669)

    @Test func splitsOnTheHingeOfTheUnfoldedDuoInLandscape() throws {
        let columns = try #require(HomeColumns.resolve(container: duoContent, isRegularWidth: true, hinge: hinge))
        #expect(columns.isHinge)
        #expect(abs(columns.leadingWidth - 455.3) < 0.01)
        #expect(abs(columns.bandWidth - 40.4) < 0.01)
        #expect(abs(columns.leadingWidth + columns.bandWidth + columns.trailingWidth - duoContent.width) < 0.01)
    }

    @Test func iPadLandscapeStaysOneColumn() {
        // Wide enough to split in a split view, but no hinge: the midpoint split is for list/detail pages only.
        #expect(HomeColumns.resolve(container: CGRect(x: 0, y: 0, width: 1194, height: 834), isRegularWidth: true, hinge: nil) == nil)
    }

    @Test func portraitCompactAndNarrowWindowsStayOneColumn() {
        // Unfolded portrait: taller than wide.
        #expect(HomeColumns.resolve(container: CGRect(x: 0, y: 0, width: 669, height: 951), isRegularWidth: true,
                                    hinge: CGRect(x: 0, y: 455, width: 669, height: 40)) == nil)
        // Folded outer display: compact, no hinge.
        #expect(HomeColumns.resolve(container: CGRect(x: 0, y: 0, width: 466, height: 678), isRegularWidth: false, hinge: nil) == nil)
        // A trailing half under 360 pt does not split.
        #expect(HomeColumns.resolve(container: CGRect(x: 0, y: 0, width: 800, height: 600), isRegularWidth: true, hinge: hinge) == nil)
    }
}
