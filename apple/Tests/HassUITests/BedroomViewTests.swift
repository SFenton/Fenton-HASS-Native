import Foundation
import HassCore
import HassDesign
@testable import HassUI
import SwiftUI
import Testing

/// Hosted renders of the bedroom sheets and tiles on every fixture, tab, layout and text size, plus the dial
/// mapping and the gallery recorder's echoes.
@MainActor
struct BedroomViewTests {
    static let phone = CGSize(width: 402, height: 874)
    static let tabletLandscape = CGSize(width: 1210, height: 834)

    func devices(_ scenario: BedroomFixtures.Scenario) -> (BedroomDevices, BedroomGalleryRecorder) {
        let store = EntityStore()
        store.replaceAll(BedroomFixtures.states(scenario))
        let recorder = BedroomGalleryRecorder(store: store)
        return (BedroomDevices(store: store, caller: recorder), recorder)
    }

    func render(_ view: some View, size: CGSize, typeSize: DynamicTypeSize = .large) -> CGImage? {
        let renderer = ImageRenderer(content: view.dynamicTypeSize(typeSize).frame(width: size.width, height: size.height))
        renderer.proposedSize = ProposedViewSize(size)
        return renderer.cgImage
    }

    @Test(arguments: BedroomFixtures.Scenario.allCases)
    func everyBedTabRendersInBothLayouts(scenario: BedroomFixtures.Scenario) {
        let (devices, _) = devices(scenario)
        for side in BedSide.allCases {
            for tab in BedSideSheet.Tab.allCases {
                #expect(render(BedSideSheet(devices: devices, side: side, initialTab: tab, window: nil), size: Self.phone) != nil)
                let window = WindowMetrics(size: Self.tabletLandscape, isRegularWidth: true)
                #expect(render(BedSideSheet(devices: devices, side: side, initialTab: tab, window: window), size: Self.tabletLandscape) != nil)
            }
        }
    }

    @Test(arguments: BedroomFixtures.Scenario.allCases)
    func wakeLightTabsRender(scenario: BedroomFixtures.Scenario) {
        let (devices, _) = devices(scenario)
        for tab in WakeLightSheet.Tab.allCases {
            #expect(render(WakeLightSheet(devices: devices, initialTab: tab), size: Self.phone) != nil)
            #expect(render(WakeLightSheet(devices: devices, initialTab: tab), size: Self.phone, typeSize: .accessibility5) != nil)
        }
        #expect(render(VStack {
            WakeLightTile(controller: devices.wakeLight) {}
            ForEach(devices.beds, id: \.config.id) { BedSideTile(controller: $0) {} }
        }, size: Self.phone) != nil)
    }

    @Test func editorsRender() {
        let (devices, _) = devices(.default)
        #expect(render(NavigationStack { WakeLightEditor(devices: devices, alarmId: nil) {} }, size: Self.phone) != nil)
        #expect(render(NavigationStack { WakeLightEditor(devices: devices, alarmId: "weekday") {} }, size: Self.phone) != nil)
        let bed = devices.bed(.left)
        #expect(render(NavigationStack { BedAlarmEditor(devices: devices, side: .left, alarmId: bed.alarms.first?.id, lockedDay: nil) {} },
                       size: Self.phone, typeSize: .accessibility3) != nil)
        #expect(render(NavigationStack { BedAlarmEditor(devices: devices, side: .left, alarmId: nil, lockedDay: .monday) {} }, size: Self.phone) != nil)
        #expect(render(NavigationStack { BedAlarmDayPage(devices: devices, side: .left, day: .monday, path: .constant([])) }, size: Self.phone) != nil)
        bed.setTarget(6)
        #expect(bed.scopeRequest != nil)
        #expect(render(BedTemperatureScopeSheet(controller: bed), size: Self.phone) != nil)
    }

    @Test func dialUsesTheSignedLevelScale() {
        let (devices, _) = devices(.default)
        let left = BedDial.configuration(devices.bed(.left))
        #expect(left.min == -10 && left.max == 10 && left.step == 1)
        #expect(left.valueStyle == .signedLevel)
        #expect(left.targets == .single(3))
        #expect(left.primaryText == "+3")
        #expect(left.actionText == "Heating")
        #expect(left.spokenValue(3) == "+3")
        #expect(left.accessibilityLabel(for: .target) == "Stephen's Bed target level")
        #expect(left.readoutAccessibilityLabel == "Stephen's Bed, Heating, target +3, currently 86.5°F")
        let (offline, _) = self.devices(.unavailable)
        let unavailable = BedDial.configuration(offline.bed(.right))
        #expect(unavailable.isUnavailable && !unavailable.acceptsInput)
        let (flash, _) = self.devices(.hotFlash)
        #expect(BedDial.configuration(flash.bed(.right)).actionText == "Hot Flash")
    }

    @Test func galleryRecorderAnswersLikeHomeAssistant() async throws {
        let (devices, recorder) = devices(.ringing)
        let bed = devices.bed(.left)
        bed.snoozeAlarm()
        await bed.waitForCalls()
        #expect(recorder.lastCall.hasPrefix("button.press"))
        #expect(bed.alarmState == .snoozed)
        bed.setPower(on: false)
        await bed.waitForCalls()
        #expect(!bed.isOn)
        var alarm = try #require(devices.wakeLight.snapshot.alarms.first)
        alarm.enabled = false
        #expect(await devices.wakeLight.save(alarm))
        #expect(devices.wakeLight.live.alarms.first?.enabled == false)
        #expect(await devices.wakeLight.updateDefaults(.standard))
        #expect(devices.wakeLight.live.defaults == .standard)
        #expect(await devices.wakeLight.setLinks(["sleepypod:left#monday#06:30"], enabled: false))
        #expect(!devices.wakeLight.live.isLinked("sleepypod:left#monday#06:30"))
        bed.createAlarms(days: [.sunday], time: "10:00")
        await bed.waitForCalls()
        #expect(bed.sourceAlarms.contains { $0.day == .sunday && $0.time == "10:00" })
    }

    @Test func galleryRecorderHandlesSoloTripCommands() async {
        let (devices, recorder) = devices(.soloTrip)
        let bed = devices.bed(.left)
        #expect(bed.scope.controlsWholeBed)
        bed.setPower(on: false)
        await bed.waitForCalls()
        #expect(recorder.lastCall.hasPrefix("script.household_away_command"))
        #expect(!devices.bed(.right).isOn)
        #expect(devices.bed(.right).scope.readOnly)
    }

    @Test func galleryPageRenders() {
        #expect(ComponentGallery.Page(rawValue: "bedroom") == .bedroom)
        #expect(render(ComponentGallery(page: .bedroom), size: Self.phone) != nil)
    }
}
