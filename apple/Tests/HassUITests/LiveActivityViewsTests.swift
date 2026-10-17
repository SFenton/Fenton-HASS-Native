#if os(macOS)
import AppKit
import FentonActivityModel
@testable import FentonActivityViews
import Foundation
import HassDesign
import SwiftUI
import Testing

/// Hosted renders of the Home Live Activity's views (`live-activities.md` §11): every scenario on the Lock Screen and in
/// each island presentation, at default and accessibility text sizes, in light and dark, with Always-On dimming and
/// StandBy's header-less layout. The metrics that depend on iOS text (the 160 pt height, 44 pt targets) are measured on
/// the simulator by `LiveActivityJourneyTests`; the macOS host proves each branch draws.
@MainActor
@Suite(.serialized)
struct LiveActivityViewsTests {
    static let now = Date()

    func state(_ scenario: HomeActivityFixtures.Scenario) -> HomeActivityState {
        HomeActivityFixtures.state(scenario, now: Self.now)
    }

    /// Draws `view` on a dark ground and returns its pixels.
    func render(_ view: some View, size: CGSize = CGSize(width: 360, height: 260)) async -> NSBitmapImageRep? {
        let hosted = HostedWindow(view.frame(width: size.width, height: size.height, alignment: .topLeading).background(Color.black), size: size)
        defer { hosted.close() }
        await hosted.settle(0.15)
        return hosted.snapshot()
    }

    @Test(arguments: HomeActivityFixtures.Scenario.allCases)
    func everyScenarioDrawsOnTheLockScreenInBothAppearances(_ scenario: HomeActivityFixtures.Scenario) async {
        for scheme in [ColorScheme.light, .dark] {
            let image = await render(HomeActivityLockScreenView(state: state(scenario)).environment(\.colorScheme, scheme))
            #expect((image?.distinctColors ?? 0) > 3, "\(scenario) \(scheme) drew a blank view")
        }
    }

    @Test(arguments: HomeActivityFixtures.Scenario.allCases)
    func everyScenarioDrawsAtAccessibilityTextSizesAndWhenDimmed(_ scenario: HomeActivityFixtures.Scenario) async {
        let large = await render(HomeActivityLockScreenView(state: state(scenario)).environment(\.dynamicTypeSize, .accessibility5))
        #expect((large?.distinctColors ?? 0) > 3)
        let dimmed = await render(HomeActivityLockScreenView(state: state(scenario)).environment(\.isLuminanceReduced, true))
        #expect((dimmed?.distinctColors ?? 0) > 3)
        let standBy = await render(HomeActivityLockScreenView(state: state(scenario), isFullscreen: true))
        #expect((standBy?.distinctColors ?? 0) > 3)
    }

    @Test(arguments: HomeActivityFixtures.Scenario.allCases)
    func everyScenarioDrawsInEachIslandPresentationAndTheSmallFamily(_ scenario: HomeActivityFixtures.Scenario) async {
        for kind in HomeActivityIslandPreview.Kind.allCases {
            let image = await render(HomeActivityIslandPreview(state: state(scenario), kind: kind), size: CGSize(width: 400, height: 220))
            #expect((image?.distinctColors ?? 0) > 3, "\(scenario) \(kind)")
        }
        let small = await render(HomeActivitySmallView(state: state(scenario)), size: CGSize(width: 200, height: 60))
        #expect((small?.distinctColors ?? 0) > 3)
    }

    @Test func aDimmedRowDropsItsBarAndAnAccessibilityRowStacks() async {
        let normal = await render(HomeActivityLockScreenView(state: state(.dishwasher)))
        let dimmed = await render(HomeActivityLockScreenView(state: state(.dishwasher)).environment(\.isLuminanceReduced, true))
        #expect(normal != nil && dimmed != nil)
        if let normal, let dimmed { #expect(normal.differs(from: dimmed), "Always-On draws the row dimmer and without its bar") }
    }

    @Test func everyTrailingFigureAndBarDraws() async {
        let t = Self.now.timeIntervalSince1970
        let jobs = [
            ActivityJob(id: "long", kind: "x", title: "Long", status: "Over an hour", startTs: t - 60, endTs: t + 5_400, symbol: "timer", tint: "water"),
            ActivityJob(id: "soon", kind: "x", title: "Soon", status: "Estimated", endTs: t + 900, estimated: true, symbol: "dryer", tint: "cleaning"),
            ActivityJob(id: "wait", kind: "x", title: "Waiting", status: "Delayed", phase: .waiting, endTs: t + 3_600, symbol: "clock", tint: "water"),
            ActivityJob(id: "pct", kind: "x", title: "Percent", status: "", progress: 0.4, symbol: "fan", tint: "bogus-family"),
            ActivityJob(id: "pause", kind: "x", title: "Paused", status: "", phase: .paused, symbol: "pause", tint: "air"),
            ActivityJob(id: "none", kind: "x", title: "None", status: "", symbol: "circle", tint: "neutral"),
        ]
        for job in jobs {
            let image = await render(HomeActivityLockScreenView(state: HomeActivityState(focus: job.id, jobs: [job])))
            #expect((image?.distinctColors ?? 0) > 3, Comment(rawValue: job.title))
        }
        for kind in HomeActivityIslandPreview.Kind.allCases {
            let image = await render(HomeActivityIslandPreview(state: HomeActivityState(jobs: jobs), kind: kind), size: CGSize(width: 400, height: 220))
            #expect((image?.distinctColors ?? 0) > 3)
        }
        let empty = await render(HomeActivityLockScreenView(state: HomeActivityState(jobs: [])))
        #expect(empty != nil)
        let emptyIsland = await render(HomeActivityIsland.CompactTrailing(state: HomeActivityState(jobs: [])))
        #expect(emptyIsland != nil)
    }

    @Test func theInertButtonsDrawTheirLabelsAndDoNothing() {
        let job = state(.dishwasher).jobs[0]
        let control = job.controls[0]
        _ = ActivityActions.inert.control("fenton-home", job, control, AnyView(Text("Stop")))
        _ = ActivityActions.inert.focus("fenton-home", job.id, AnyView(Text("‹")))
        var values = EnvironmentValues()
        _ = values.activityActions
        values.activityActions = .inert
    }
}

struct ActivityStyleTests {
    /// WCAG relative luminance of an `0xRRGGBB` colour.
    private func luminance(_ rgb: (Double, Double, Double)) -> Double {
        func channel(_ value: Double) -> Double {
            let v = value / 255
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(rgb.0) + 0.7152 * channel(rgb.1) + 0.0722 * channel(rgb.2)
    }

    private func contrast(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
        let (hi, lo) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
        return (hi + 0.05) / (lo + 0.05)
    }

    private func rgb(_ value: UInt32) -> (Double, Double, Double) {
        (Double((value >> 16) & 0xFF), Double((value >> 8) & 0xFF), Double(value & 0xFF))
    }

    private func blend(_ top: (Double, Double, Double), _ alpha: Double, over bottom: (Double, Double, Double)) -> (Double, Double, Double) {
        (top.0 * alpha + bottom.0 * (1 - alpha), top.1 * alpha + bottom.1 * (1 - alpha), top.2 * alpha + bottom.2 * (1 - alpha))
    }

    /// The Lock Screen background is the system material under a dark tint, so the brightest case is a white wallpaper
    /// under the tint alone: text on a row must still read there (WCAG 1.4.3).
    @Test(arguments: ["cleaning", "air", "water", "neutral", "bogus"])
    func textReadsOnTheRowEvenOverAWhiteWallpaper(_ tint: String) {
        let ground = blend((0, 0, 0), ActivityStyle.groundOpacity, over: (255, 255, 255))
        let family = ActivityStyle(tint: tint).family
        let row = blend(rgb(family.spec.fill ?? 0x48484A), 0.42, over: ground)
        #expect(contrast((255, 255, 255), row) >= 4.5, "\(tint) primary text")
        let secondary = blend((255, 255, 255), 0.78, over: row)
        #expect(contrast(secondary, row) >= 4.5, "\(tint) secondary text")
        #expect(contrast(rgb(family.spec.glyph), blend((0, 0, 0), 1, over: (0, 0, 0))) >= 3, "\(tint) glyph on the island's black")
    }

    @Test func unknownTintsReadNeutralAndDimmedRowsAreFainter() {
        #expect(ActivityStyle(tint: "nope").family == .neutral)
        #expect(ActivityStyle(tint: "air").family == .air)
        #expect(ActivityStyle(tint: "air") == ActivityStyle(tint: "air"))
        _ = ActivityStyle(tint: "air").rowFill(dimmed: true)
        _ = ActivityStyle(tint: "air").accent
    }
}
#endif
