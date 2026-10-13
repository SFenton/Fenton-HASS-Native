@testable import HassDesign
import SwiftUI
import Testing

struct BrightnessTileTests {
    @Test func dragPositionMapsAcrossTheTile() {
        #expect(BrightnessTile.percent(atX: 0, width: 200) == 0)
        #expect(BrightnessTile.percent(atX: 50, width: 200) == 25)
        #expect(BrightnessTile.percent(atX: 260, width: 200) == 100)
        #expect(BrightnessTile.percent(atX: -10, width: 200) == 0)
        #expect(BrightnessTile.percent(atX: 10, width: 0) == 0)
    }

    @Test func adjustStepsClamp() {
        #expect(BrightnessTile.stepped(45, by: BrightnessTile.step) == 55)
        #expect(BrightnessTile.stepped(95, by: 10) == 100)
        #expect(BrightnessTile.stepped(5, by: -10) == 0)
    }

    @Test func statusReadsOffPercentOrUnavailable() {
        #expect(BrightnessTile.status(percent: 0, isUnavailable: false) == "Off")
        #expect(BrightnessTile.status(percent: 45, isUnavailable: false) == "45%")
        #expect(BrightnessTile.status(percent: 45, isUnavailable: true) == "Unavailable")
    }

    @MainActor
    @Test func rendersOnOffAndUnavailable() {
        for (percent, unavailable) in [(0, false), (60, false), (0, true)] {
            let tile = BrightnessTile(title: "Gym", tint: .yellow, fillTint: .orange, percent: percent, isUnavailable: unavailable, onPower: { _ in }, onBrightness: { _ in })
                .frame(width: 170)
            #expect(ImageRenderer(content: tile).cgImage != nil)
        }
    }
}

struct BrightnessInteractionTests {
    @Test func cancelledDragCommitsNothing() {
        var state = BrightnessInteraction()
        state.dragChanged(translation: CGSize(width: 20, height: 2), x: 60, width: 200)
        #expect(state.shown(live: 80) == 30)
        state.dragCancelled()
        #expect(state.shown(live: 80) == 80)
        #expect(state.dragEnded(x: 60, width: 200, live: 80) == nil)
    }

    @Test func tapTurnsOnShowingFullThenOff() {
        var state = BrightnessInteraction()
        #expect(state.flip(live: 0, isUnavailable: false) == .power(true))
        #expect(state.shown(live: 0) == 100)
        #expect(state.flip(live: 40, isUnavailable: false) == .power(false))
        #expect(state.shown(live: 40) == 0)
        state.pendingPercent = nil
        #expect(state.shown(live: 40) == 40)
    }

    @Test func unavailableIgnoresTapAndAdjust() {
        var state = BrightnessInteraction()
        #expect(state.flip(live: 0, isUnavailable: true) == nil)
        #expect(state.adjust(by: 10, live: 0, isUnavailable: true) == nil)
        #expect(state == BrightnessInteraction())
    }

    @Test func adjustStepsFromTheShownValueAndSkipsNoOps() {
        var state = BrightnessInteraction()
        #expect(state.adjust(by: 10, live: 45, isUnavailable: false) == .brightness(55))
        #expect(state.adjust(by: 10, live: 45, isUnavailable: false) == .brightness(65))
        #expect(state.adjust(by: 10, live: 100, isUnavailable: false) == .brightness(75))
        var full = BrightnessInteraction()
        #expect(full.adjust(by: 10, live: 100, isUnavailable: false) == nil)
        #expect(full.adjust(by: -10, live: 5, isUnavailable: false) == .brightness(0))
    }

    @Test func horizontalDragFollowsTheFingerAndCommitsOnRelease() {
        var state = BrightnessInteraction()
        state.dragChanged(translation: CGSize(width: 20, height: 3), x: 60, width: 200)
        #expect(state.dragAxis == .horizontal)
        #expect(state.shown(live: 0) == 30)
        state.dragChanged(translation: CGSize(width: 2, height: 40), x: 140, width: 200)
        #expect(state.shown(live: 0) == 70)
        #expect(state.dragEnded(x: 140, width: 200, live: 0) == .brightness(70))
        #expect(state.dragAxis == nil && state.dragPercent == nil)
        #expect(state.shown(live: 0) == 70)
    }

    @Test func verticalDragIsLeftToTheScrollView() {
        var state = BrightnessInteraction()
        state.dragChanged(translation: CGSize(width: 2, height: 30), x: 150, width: 200)
        #expect(state.dragAxis == .vertical && state.dragPercent == nil)
        #expect(state.dragEnded(x: 150, width: 200, live: 20) == nil)
        #expect(state.dragAxis == nil)
    }

    @Test func dragEndingAtTheLiveLevelSendsNothing() {
        var state = BrightnessInteraction()
        state.dragChanged(translation: CGSize(width: 10, height: 0), x: 100, width: 200)
        #expect(state.dragEnded(x: 100, width: 200, live: 50) == nil)
        #expect(state.pendingPercent == nil)
    }
}
