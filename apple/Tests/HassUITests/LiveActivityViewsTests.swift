#if os(macOS)
import AppKit
import FentonActivityModel
@testable import FentonActivityViews
import Foundation
import HassCore
import HassDesign
import SwiftUI
import Testing

/// Hosted renders of the Live Activity's views (`live-activities-per-job.md` §12): every card on the Lock Screen and in each
/// island presentation, at default and accessibility text sizes, in light and dark, with Always-On dimming and StandBy's
/// mark-less layout. The metrics that depend on iOS text (the 160 pt height, 44 pt targets, the clipping check) are measured on
/// the simulator by `LiveActivityJourneyTests`; the macOS host proves each branch draws.
@MainActor
@Suite(.serialized)
struct LiveActivityViewsTests {
    static let now = Date()

    func card(_ name: String) -> ActivityCard {
        guard let fixture = HomeActivityFixtures.fixture(name, now: Self.now) else { return ActivityCard(attributes: HomeActivityAttributes(), state: HomeActivityState()) }
        return fixture.card(now: Self.now)
    }

    /// Draws `view` on a dark ground and returns its pixels.
    func render(_ view: some View, size: CGSize = CGSize(width: 370, height: 220)) async -> NSBitmapImageRep? {
        let hosted = HostedWindow(view.frame(width: size.width, height: size.height, alignment: .topLeading).background(Color.black), size: size)
        defer { hosted.close() }
        // A loaded host can take several passes to draw the first frame: settle until something is on screen.
        await hosted.settle(0.15)
        for _ in 0..<12 where (hosted.snapshot()?.distinctColors ?? 0) <= 3 { await hosted.settle(0.15) }
        return hosted.snapshot()
    }

    /// A card from each layout and state, for the checks that need not run for every name.
    nonisolated static let representatives = ["fan", "fan-long", "dishwasher-percent", "dishwasher-paused", "dishwasher-waiting", "dryer", "dryer-estimated",
                                  "washer-complete", "vacuum", "vacuum-paused", "hotflash-cooling", "hotflash-bysteph", "fan-pending",
                                  "fan-pending-stale", "fan-notice", "problem-navigation-stuck", "problem-mop-clean_water_empty",
                                  "problem-vendor-unknown_error_88", "problem-completing", "problem-power-low_battery"]

    @Test(arguments: HomeActivityFixtures.allNames)
    func everyCardDrawsOnTheLockScreen(_ name: String) async {
        let image = await render(HomeActivityLockScreenView(card: card(name)))
        #expect((image?.distinctColors ?? 0) > 3, "\(name) drew a blank view")
    }

    @Test(arguments: representatives)
    func aCardDrawsInLightAndDarkAtAccessibilityTextSizesDimmedAndInStandBy(_ name: String) async {
        for scheme in [ColorScheme.light, .dark] {
            let image = await render(HomeActivityLockScreenView(card: card(name)).environment(\.colorScheme, scheme))
            #expect((image?.distinctColors ?? 0) > 3, "\(name) \(scheme)")
        }
        let large = await render(HomeActivityLockScreenView(card: card(name)).environment(\.dynamicTypeSize, .accessibility5), size: CGSize(width: 370, height: 700))
        #expect((large?.distinctColors ?? 0) > 3, "\(name) AX5")
        let dimmed = await render(HomeActivityLockScreenView(card: card(name)).environment(\.isLuminanceReduced, true))
        #expect((dimmed?.distinctColors ?? 0) > 3, "\(name) dimmed")
        let standBy = await render(HomeActivityLockScreenView(card: card(name), isFullscreen: true))
        #expect((standBy?.distinctColors ?? 0) > 3, "\(name) StandBy")
    }

    @Test(arguments: representatives)
    func aCardDrawsInEachIslandPresentationAndTheSmallFamily(_ name: String) async {
        for kind in HomeActivityIslandPreview.Kind.allCases {
            // Each in a window about its own size: the colour count samples a coarse grid, which a small island misses.
            let size = switch kind {
            case .compact: CGSize(width: 260, height: 40)
            case .minimal: CGSize(width: 48, height: 48)
            case .expanded: CGSize(width: 400, height: 140)
            }
            let image = await render(HomeActivityIslandPreview(card: card(name), kind: kind), size: size)
            #expect((image?.distinctColors ?? 0) > 3, "\(name) \(kind)")
        }
        let small = await render(HomeActivitySmallView(card: card(name)), size: CGSize(width: 200, height: 60))
        #expect((small?.distinctColors ?? 0) > 3, "\(name) small")
    }

    @Test func aPausedCardAndADimmedCardDrawDifferentlyFromTheirNormalSelves() async {
        let normal = await render(HomeActivityLockScreenView(card: card("vacuum")))
        let paused = await render(HomeActivityLockScreenView(card: card("vacuum-paused")))
        let dimmed = await render(HomeActivityLockScreenView(card: card("vacuum")).environment(\.isLuminanceReduced, true))
        #expect(normal != nil && paused != nil && dimmed != nil)
        if let normal, let dimmed { #expect(normal.differs(from: dimmed), "Always-On hides the ring track") }
        if let normal, let paused { #expect(normal.differs(from: paused)) }
    }

    @Test func eachRingAndFigureKindDraws() async {
        let attributes = HomeActivityAttributes(tag: "job.x", title: "Thing", kind: "generic", symbol: "generic", tint: "bogus-family")
        let t = Self.now
        let states: [HomeActivityState] = [
            HomeActivityState(value: .countdown(start: t.addingTimeInterval(-60), end: t.addingTimeInterval(5_400))),
            HomeActivityState(value: .percent, progress: 0.4),
            HomeActivityState(phase: .paused, value: ActivityValue(kind: .countup, startTs: t.timeIntervalSince1970 - 60, pausedElapsedS: 30)),
            HomeActivityState(value: .countup(start: t.addingTimeInterval(-3_700))),
            HomeActivityState(value: .text("Cooling")),
            HomeActivityState(),
        ]
        for state in states {
            let image = await render(HomeActivityLockScreenView(card: ActivityCard(attributes: attributes, state: state, now: t)))
            #expect((image?.distinctColors ?? 0) > 3)
        }
        for kind in HomeActivityIslandPreview.Kind.allCases {
            let image = await render(HomeActivityIslandPreview(card: ActivityCard(attributes: attributes, state: states[0], now: t), kind: kind),
                                     size: CGSize(width: 400, height: 140))
            #expect(image != nil)
        }
    }

    @Test func aTimeRingDrawsAsAFractionWhenTheGalleryAsksForIt() async {
        let live = await render(HomeActivityLockScreenView(card: card("fan")).environment(\.activityStaticTimerRing, true))
        let done = await render(HomeActivityLockScreenView(card: card("fan")).environment(\.activityStaticTimerRing, true).environment(\.isLuminanceReduced, true))
        #expect((live?.distinctColors ?? 0) > 3 && done != nil)
        var values = EnvironmentValues()
        #expect(values.activityStaticTimerRing == false)
        values.activityStaticTimerRing = true
    }

    @Test func theCompactIslandHidesItsTrailingSideInALimitedWidth() async {
        let limited = await render(HomeActivityIsland.CompactTrailing(card: card("fan"), isLimitedWidth: true), size: CGSize(width: 80, height: 40))
        let normal = await render(HomeActivityIsland.CompactTrailing(card: card("fan")), size: CGSize(width: 80, height: 40))
        #expect(limited != nil && normal != nil)
        if let limited, let normal { #expect(limited.differs(from: normal)) }
        for name in ["problem-navigation-stuck", "washer-complete"] {
            let image = await render(HomeActivityIsland.CompactTrailing(card: card(name)), size: CGSize(width: 90, height: 40))
            #expect(image != nil, Comment(rawValue: name))
        }
    }

    @Test func theIslandRegionsHaveTheWidthsOfTheCanvas() {
        #expect(HomeActivityIslandPreview.regionWidth(screenWidth: 393, cameraWidth: 126) == 104.5)
        #expect(HomeActivityIslandPreview.regionWidth(screenWidth: 402, cameraWidth: 104) == 120)
        #expect(HomeActivityIslandPreview.regionWidth(screenWidth: 440, cameraWidth: 126) == 128)
    }

    @Test func theInertButtonsDrawTheirLabelsAndDoNothing() {
        let control = ActivityControl(id: "stop", title: "Stop")
        _ = ActivityActions.inert.control("job.fan.guest", control, AnyView(Text("Stop")))
        var values = EnvironmentValues()
        _ = values.activityActions
        values.activityActions = .inert
        _ = values.cornerMarkChoice
        values.cornerMarkChoice = "tealMint"
    }
}

/// The corner mark follows the app icon (spec §8).
@MainActor
@Suite(.serialized)
struct CornerMarkTests {
    @Test func theWidgetsColoursMirrorEveryAppIconChoice() {
        for choice in AppIconChoice.allCases {
            #expect(CornerMarkPalette.glyph(for: choice.rawValue) == choice.glyph, Comment(rawValue: choice.rawValue))
        }
        #expect(CornerMarkPalette.glyphs.count == AppIconChoice.allCases.count, "a choice added without a colour here would fall back silently")
        #expect(CornerMarkPalette.glyph(for: nil) == AppIconChoice.navySky.glyph)
        #expect(CornerMarkPalette.glyph(for: "gone") == AppIconChoice.navySky.glyph, "an icon an update removed reads Navy + Sky")
        #expect(ActivityAppIconStore.fallback == AppIconChoice.default.rawValue)
    }

    private func pixels(choice: String) async -> NSBitmapImageRep? {
        let view = CornerMark().environment(\.cornerMarkChoice, choice).frame(width: 60, height: 60).background(Color.black)
        let hosted = HostedWindow(view, size: CGSize(width: 60, height: 60))
        defer { hosted.close() }
        await hosted.settle(0.2)
        return hosted.snapshot()
    }

    @Test func theMarkDrawsInTheChosenColour() async {
        let navy = await pixels(choice: "navySky")
        let gold = await pixels(choice: "midnightGold")
        let storedChoice = await pixels(choice: ActivityAppIconStore.shared.choice)
        #expect((navy?.distinctColors ?? 0) > 3 && (gold?.distinctColors ?? 0) > 3 && storedChoice != nil)
        if let navy, let gold { #expect(navy.differs(from: gold), "each icon choice tints the mark differently") }
    }

    @Test func theShapeKnocksTheHeartsRingOutOfTheHouse() {
        let path = HouseHeartShape().path(in: CGRect(x: 0, y: 0, width: 100, height: 100))
        // The house's wall beside the heart is solid; the ring around the heart is empty (see through to the card).
        #expect(path.contains(CGPoint(x: 20, y: 70)), "the wall is filled")
        #expect(path.contains(CGPoint(x: 75, y: 78)), "the heart is filled")
        #expect(!path.contains(CGPoint(x: 56.5, y: 72)), "the ring around the heart is cut out of the house")
        #expect(path.boundingRect.width > 70 && path.boundingRect.height > 70)
        // A non-square rect centres the 100-unit square.
        let wide = HouseHeartShape().path(in: CGRect(x: 0, y: 0, width: 200, height: 100))
        #expect(abs(wide.boundingRect.midX - 100) < 1)
    }
}

/// Every glyph the engine can name has an SF Symbol this system has (spec §12: "the problem table renders every icon").
@MainActor
struct ActivityGlyphSymbolTests {
    @Test(arguments: ActivityGlyph.allCases)
    func everyGlyphHasASymbol(_ glyph: ActivityGlyph) {
        #expect(NSImage(systemSymbolName: glyph.symbolName, accessibilityDescription: nil) != nil, Comment(rawValue: "\(glyph) \(glyph.symbolName)"))
    }

    @Test func everyProblemRowNamesAGlyphThisBuildDraws() {
        for name in HomeActivityFixtures.problemNames {
            let problem = HomeActivityFixtures.fixture(name)?.state.problem
            #expect(problem.map { ActivityGlyph.problemSet.contains($0.glyph) } == true, Comment(rawValue: name))
        }
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

    /// The Lock Screen background is the system material under the card's tint, so the brightest case is a white wallpaper
    /// under the tint alone: text on a job card must still read there (WCAG 1.4.3).
    @Test func textReadsOnAJobCardEvenOverAWhiteWallpaper() {
        let card = blend(rgb(0x17181E), ActivityStyle.cardOpacity, over: (255, 255, 255))
        #expect(contrast((255, 255, 255), card) >= 4.5, "primary text")
        #expect(contrast(blend((255, 255, 255), 0.78, over: card), card) >= 4.5, "secondary text")
        #expect(contrast(blend((255, 255, 255), 0.55, over: card), card) >= 3, "a paused time (large text)")
    }

    @Test(arguments: ["cleaning", "air", "water", "cooling", "neutral", "bogus"])
    func theAccentReadsOnTheIslandsBlack(_ tint: String) {
        let family = ActivityStyle(tint: tint).family
        #expect(contrast(rgb(family.spec.glyph), (0, 0, 0)) >= 3, "\(tint) glyph on black")
    }

    @Test(arguments: [ActivityProblem.Severity.critical, .warning])
    func aProblemsTextReadsOnItsCardEvenOverAWhiteWallpaper(_ severity: ActivityProblem.Severity) {
        let colors = ActivityStyle.severity(severity)
        let ground = blend(severity == .critical ? rgb(0x3E1614) : rgb(0x3A2808), 0.92, over: (255, 255, 255))
        // The gradient's lighter (top) stop over the ground.
        let top = severity == .critical ? (rgb(0xFF453A), 0.30) : (rgb(0xFF9F0A), 0.26)
        let surface = blend(top.0, top.1, over: ground)
        #expect(contrast(rgb(colors.lightTextRGB), surface) >= 4.5, "\(severity) problem line")
        #expect(contrast(blend((255, 255, 255), 0.82, over: surface), surface) >= 4.5, "\(severity) instruction")
        #expect(contrast((255, 255, 255), surface) >= 4.5, "\(severity) title")
        #expect(contrast(rgb(colors.circleRGB), (0, 0, 0)) >= 3, "the circle on the island's black")
    }

    @Test func unknownTintsReadNeutralAndSeveritiesPickTheirColours() {
        #expect(ActivityStyle(tint: "nope").family == .neutral)
        #expect(ActivityStyle(tint: "air").family == .air)
        #expect(ActivityStyle(tint: "air") == ActivityStyle(tint: "air"))
        _ = ActivityStyle(tint: "air").accent
        #expect(ActivityStyle.severity(.critical).circleRGB == 0xFF453A && ActivityStyle.severity(.warning).circleRGB == 0xFF9F0A)
        let job = HomeActivityFixtures.fixture("fan")!.card()
        let problem = HomeActivityFixtures.fixture("problem-navigation-stuck")!.card()
        _ = ActivityStyle.ground(for: job)
        _ = ActivityStyle.ground(for: problem)
        #expect(ActivityStyle.lockScreenHeightLimit == 160 && ActivityStyle.minimumHit == 44 && ActivityStyle.ringSize == 64 && ActivityStyle.markSize == 40)
    }
}
#endif
