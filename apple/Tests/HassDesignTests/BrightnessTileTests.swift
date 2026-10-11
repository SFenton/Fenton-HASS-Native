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
