#if os(macOS)
import AppKit
import Foundation
import HassCore
@testable import HassDesign
@testable import HassUI
import SwiftUI
import Testing

/// The bathroom fan sheet reports the height of its own content to a fitted sheet (owner, 2026-10-17: "sheet height fits
/// its content, no empty band"). A hosted window stands in for the presentation: the reading must be about the size of
/// the controls, idle and while a timer runs.
@MainActor
struct BathroomFanSheetFitTests {
    func reading(power: String, locked: Bool, pending: Bool) -> CGFloat? {
        let fan = BathroomFanConfig.guest
        let store = EntityStore()
        store.replaceAll(RoomDeviceFixture.fanStates(fan, power: power, locked: locked, pending: pending, now: Date()))
        let model = SheetFitModel()
        let sheet = BathroomFanSheet(config: fan, store: store, caller: RecordingCaller())
            .environment(\.sheetFit, model)
        let host = SheetHostWindow(sheet, size: CGSize(width: 402, height: 874))
        for _ in 0..<10 where model.contentHeight == nil { host.settle(0.2) }
        host.settle(0.5)
        return model.contentHeight
    }

    @Test func anIdleFanSheetFitsItsControls() throws {
        let height = try #require(reading(power: "off", locked: false, pending: false))
        print("FITIDLE \(height)"); #expect(height < 560, "Idle fan sheet reported \(height) pt")
    }

    @Test func aTimedFanSheetFitsItsControls() throws {
        let height = try #require(reading(power: "on", locked: true, pending: true))
        print("FITTIMED \(height)"); #expect(height < 560, "Timed fan sheet reported \(height) pt")
    }
}
#endif
