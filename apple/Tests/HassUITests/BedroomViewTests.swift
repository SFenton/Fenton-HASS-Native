import AppKit
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
        #expect(left.scale == .signedLevel && left.valueStyle == nil)
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

    @Test func galleryRecorderEchoesHotFlashStagesAndEpisodes() async throws {
        let (devices, _) = devices(.waking)
        let right = devices.bed(.right)
        right.startHotFlash()
        await right.waitForCalls()
        #expect(right.hotFlashActive)
        right.cancelHotFlash()
        await right.waitForCalls()
        #expect(!right.hotFlashActive)
        // The right side is outside its schedule, so a stage step writes the level and republishes the schedule.
        let before = try #require(right.stageLevel(.bedtime))
        right.stepStage(.bedtime, up: true)
        for _ in 0..<200 where right.stageLevel(.bedtime) == before { try? await Task.sleep(for: .milliseconds(20)) }
        await right.waitForCalls()
        #expect(right.stageLevel(.bedtime) == before + 1)
        // Deleting an alarm and ending the running wake both come back accepted and change the state.
        #expect(devices.wakeLight.snapshot.activeOccurrences.count == 1)
        #expect(await devices.wakeLight.delete(alarmId: "weekend"))
        #expect(await devices.wakeLight.endEpisode())
        #expect(devices.wakeLight.live.activeOccurrences.isEmpty)
        #expect(!devices.wakeLight.live.alarms.contains { $0.id == "weekend" })
    }

    @Test func galleryRecorderAppliesSoloTripStageAndAlarmCommands() async throws {
        let (devices, _) = devices(.soloTrip)
        let bed = devices.bed(.left)
        let before = try #require(bed.stageLevel(.bedtime))
        bed.stepStage(.bedtime, up: true)
        for _ in 0..<200 where bed.stageLevel(.bedtime) == before { try? await Task.sleep(for: .milliseconds(20)) }
        await bed.waitForCalls()
        bed.createAlarms(days: [.sunday], time: "11:00")
        await bed.waitForCalls()
        for _ in 0..<200 where !bed.sourceAlarms.contains(where: { $0.day == .sunday }) { try? await Task.sleep(for: .milliseconds(20)) }
        #expect(bed.sourceAlarms.contains { $0.day == .sunday && $0.time == "11:00" })
    }

    @Test func galleryPageRenders() {
        #expect(ComponentGallery.Page(rawValue: "bedroom") == .bedroom)
        #expect(render(ComponentGallery(page: .bedroom), size: Self.phone) != nil)
    }
}

// MARK: - Hosted in a real window

/// A caller that answers from a script, so a view test can drive failures and refusals without Home Assistant.
@MainActor
final class ScriptedCaller: HassServiceResponding {
    var fail = false
    var responses: [JSONValue] = []
    private(set) var calls: [String] = []

    struct Failure: Error {}

    func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {
        calls.append("\(domain).\(service)")
        if fail { throw Failure() }
    }

    func callServiceWithResponse(_ domain: String, _ service: String, data: [String: any Sendable]) async throws -> JSONValue {
        calls.append("\(domain).\(service)")
        if fail { throw Failure() }
        return responses.isEmpty ? .object(["outcome": "accepted"]) : responses.removeFirst()
    }
}

/// A SwiftUI view in an off-screen `NSWindow`. Unlike `ImageRenderer` this evaluates scroll views, navigation
/// stacks, sheets and timelines, so every branch of a sheet's body runs.
@MainActor
final class HostedView {
    let window: NSWindow
    let host: NSHostingView<AnyView>

    init(_ content: some View, size: CGSize, typeSize: DynamicTypeSize = .large) {
        _ = NSApplication.shared
        host = NSHostingView(rootView: AnyView(content
            .environment(\.dynamicTypeSize, typeSize)
            .environment(\.colorScheme, .dark)
            .frame(width: size.width, height: size.height)
            .background(Color.black)))
        window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -4000, y: -4000), size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderBack(nil)
    }

    /// Lets SwiftUI run its update passes after a state change.
    func settle(rounds: Int = 3) async {
        for _ in 0..<rounds {
            try? await Task.sleep(for: .milliseconds(40))
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
        }
    }

    /// A hash of the drawn pixels: changes when the view's content changes.
    var fingerprint: Int {
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return 0 }
        host.cacheDisplay(in: host.bounds, to: rep)
        var hasher = Hasher()
        hasher.combine(rep.tiffRepresentation ?? Data())
        return hasher.finalize()
    }

    /// How many distinct colors the sampled pixels hold; a blank view has one.
    var distinctColors: Int {
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return 0 }
        host.cacheDisplay(in: host.bounds, to: rep)
        var colors = Set<UInt32>()
        for y in stride(from: 0, to: rep.pixelsHigh, by: 7) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 7) {
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                colors.insert(UInt32(color.redComponent * 255) << 16 | UInt32(color.greenComponent * 255) << 8 | UInt32(color.blueComponent * 255))
            }
        }
        return colors.count
    }

    func close() {
        window.orderOut(nil)
        window.close()
    }
}

@MainActor
@Suite(.serialized)
struct HostedBedroomTests {
    static let phone = BedroomViewTests.phone
    static let tablet = BedroomViewTests.tabletLandscape

    func devices(_ scenario: BedroomFixtures.Scenario, canEdit: Bool = true, caller: HassServiceResponding? = nil,
                 tweak: (EntityStore) -> Void = { _ in }) -> BedroomDevices {
        let store = EntityStore()
        store.replaceAll(BedroomFixtures.states(scenario))
        tweak(store)
        return BedroomDevices(store: store, caller: caller ?? BedroomGalleryRecorder(store: store), canEdit: canEdit)
    }

    /// Hosts `view`, checks it drew something, and returns it for further state changes.
    func show(_ view: some View, size: CGSize = HostedBedroomTests.phone, typeSize: DynamicTypeSize = .large) async -> HostedView {
        let hosted = HostedView(view, size: size, typeSize: typeSize)
        await hosted.settle()
        #expect(hosted.distinctColors > 3)
        return hosted
    }

    func setState(_ devices: BedroomDevices, _ id: String, _ change: (inout EntityState) -> Void) {
        let store = devices.wakeLight.store
        var entity = store.value(id) ?? EntityState(entityId: id, state: "unknown")
        change(&entity)
        store.apply([entity])
    }

    // MARK: Bed sheet

    @Test(arguments: BedroomFixtures.Scenario.allCases)
    func bedSheetHeroShowsEveryScenario(scenario: BedroomFixtures.Scenario) async {
        let devices = devices(scenario)
        for side in BedSide.allCases {
            let hosted = await show(BedSideSheet(devices: devices, side: side, initialTab: .temperature, window: nil))
            hosted.close()
        }
    }

    @Test(arguments: BedSideSheet.Tab.allCases)
    func bedSheetTabsRenderStackedAndSplit(tab: BedSideSheet.Tab) async {
        let devices = devices(.ringing)
        let stacked = await show(BedSideSheet(devices: devices, side: .left, initialTab: tab, window: nil))
        stacked.close()
        let window = WindowMetrics(size: Self.tablet, isRegularWidth: true)
        let split = await show(BedSideSheet(devices: devices, side: .left, initialTab: tab, window: window), size: Self.tablet)
        split.close()
        let large = await show(BedSideSheet(devices: devices, side: .right, initialTab: tab, window: nil), typeSize: .accessibility5)
        large.close()
    }

    @Test func publicInitializerHostsTheSheet() async {
        let hosted = await show(BedSideSheet(devices: devices(.default), side: .left))
        hosted.close()
    }

    @Test func scopeQuestionAppearsAndClearsWithTheController() async {
        let devices = devices(.default)
        let bed = devices.bed(.left)
        let hosted = await show(BedSideSheet(devices: devices, side: .left, initialTab: .temperature, window: nil))
        let before = hosted.fingerprint
        bed.setTarget(6)
        #expect(bed.scopeRequest != nil)
        await hosted.settle(rounds: 6)
        bed.chooseScope(.tonight)
        #expect(bed.scopeRequest == nil)
        await hosted.settle(rounds: 6)
        #expect(hosted.fingerprint != before)
        hosted.close()
    }

    @Test func heroShowsARefusedSoloTripCommand() async {
        let caller = ScriptedCaller()
        caller.responses = [.object(["outcome": "rejected", "error_code": "revision_conflict"])]
        let devices = devices(.soloTrip, caller: caller)
        let bed = devices.bed(.left)
        let hosted = await show(BedSideSheet(devices: devices, side: .left, initialTab: .temperature, window: nil))
        let before = hosted.fingerprint
        bed.setPower(on: false)
        await bed.waitForCalls()
        #expect(bed.isOn)
        #expect(bed.commandError != nil)
        await hosted.settle()
        #expect(hosted.fingerprint != before)
        hosted.close()
    }

    @Test func aFailedPowerOffRevertsWithoutAnError() async {
        let caller = ScriptedCaller()
        caller.fail = true
        let devices = devices(.default, caller: caller)
        let bed = devices.bed(.left)
        let hosted = await show(BedSideSheet(devices: devices, side: .left, initialTab: .temperature, window: nil))
        bed.setPower(on: false)
        await bed.waitForCalls()
        #expect(bed.isOn)
        #expect(caller.calls == ["script.sleepypod_hot_flash_broker"])
        hosted.close()
    }

    @Test func ringingAlarmGivesWayToTheSnoozeCountdown() async {
        let devices = devices(.ringing)
        let bed = devices.bed(.left)
        let hosted = await show(BedSideSheet(devices: devices, side: .left, initialTab: .temperature, window: nil))
        bed.snoozeAlarm()
        #expect(bed.alarmState == .snoozed)
        await hosted.settle()
        bed.stopAlarm()
        #expect(bed.alarmState == .idle)
        await hosted.settle()
        hosted.close()
    }

    @Test func soloTripTravelerSideIsReadOnlyInEveryTab() async {
        let devices = devices(.soloTrip)
        for tab in BedSideSheet.Tab.allCases {
            let traveler = await show(BedSideSheet(devices: devices, side: .right, initialTab: tab, window: nil))
            traveler.close()
            let resident = await show(BedSideSheet(devices: devices, side: .left, initialTab: tab, window: nil))
            resident.close()
        }
    }

    @Test func statusTabFlagsAPumpProblem() async {
        let devices = devices(.default)
        let hosted = await show(BedStatusTab(controller: devices.bed(.left)))
        let before = hosted.fingerprint
        setState(devices, MasterBedroom.stephensBed.pumpClogEntityId) { $0.state = "on" }
        await hosted.settle()
        #expect(hosted.fingerprint != before)
        hosted.close()
    }

    @Test func specialModesShowTheCountdownAndCancel() async {
        let devices = devices(.hotFlash)
        let hosted = await show(BedSpecialModesTab(controller: devices.bed(.right)))
        hosted.close()
        let idle = await show(BedSpecialModesTab(controller: devices.bed(.left)))
        idle.close()
        let offline = self.devices(.unavailable)
        let unavailable = await show(BedSpecialModesTab(controller: offline.bed(.left)))
        unavailable.close()
    }

    @Test func alarmsTabCoversEmptyMissingAndPopulatedSchedules() async {
        let populated = await show(BedAlarmsTab(controller: devices(.default).bed(.left), path: .constant([])))
        populated.close()
        let empty = devices(.default) { store in
            var entity = store.value(MasterBedroom.scheduleEntityId)!
            entity.attributes["left"] = .object([:])
            store.apply([entity])
        }
        let none = await show(BedAlarmsTab(controller: empty.bed(.left), path: .constant([])))
        none.close()
        let missing = devices(.default) { store in
            var entity = store.value(MasterBedroom.scheduleEntityId)!
            entity.state = "unavailable"
            store.apply([entity])
        }
        let unavailable = await show(BedAlarmsTab(controller: missing.bed(.left), path: .constant([])))
        unavailable.close()
        let soloTraveler = devices(.soloTrip)
        let readOnly = await show(BedAlarmsTab(controller: soloTraveler.bed(.right), path: .constant([])))
        readOnly.close()
    }

    @Test func dayPagesAndEditorsRender() async {
        let devices = devices(.ringing)
        let bed = devices.bed(.left)
        for day in [Weekday.saturday, .monday, .sunday] {
            let page = await show(NavigationStack { BedAlarmDayPage(devices: devices, side: .left, day: day, path: .constant([])) })
            page.close()
        }
        let saturday = bed.alarms.first { $0.day == .saturday }?.id
        for (id, locked) in [(saturday, nil), (nil, nil), (nil, Weekday.friday)] as [(String?, Weekday?)] {
            let editor = await show(NavigationStack { BedAlarmEditor(devices: devices, side: .left, alarmId: id, lockedDay: locked) {} })
            editor.close()
        }
        let large = await show(NavigationStack { BedAlarmEditor(devices: devices, side: .left, alarmId: saturday, lockedDay: nil) {} },
                               typeSize: .accessibility3)
        large.close()
    }

    @Test func editorShowsProblemsAndTheWakeLightError() async {
        let caller = ScriptedCaller()
        caller.responses = [.object(["outcome": "rejected", "error_code": "transport"])]
        let devices = devices(.default, caller: caller)
        var alarm = devices.wakeLight.snapshot.alarms[0]
        alarm.enabled = false
        #expect(await devices.wakeLight.save(alarm) == false)
        #expect(devices.wakeLight.error != nil)
        let editor = await show(NavigationStack { BedAlarmEditor(devices: devices, side: .left, alarmId: nil, lockedDay: nil) {} })
        editor.close()
        let offline = self.devices(.unavailable)
        let readOnly = await show(NavigationStack { BedAlarmEditor(devices: offline, side: .right, alarmId: nil, lockedDay: .monday) {} })
        readOnly.close()
    }

    @Test func tilesShowEveryScenarioAndTextSize() async {
        for scenario in BedroomFixtures.Scenario.allCases {
            let devices = devices(scenario)
            let tiles = await show(VStack {
                WakeLightTile(controller: devices.wakeLight) {}
                ForEach(devices.beds, id: \.config.id) { BedSideTile(controller: $0) {} }
            }, typeSize: .accessibility5)
            tiles.close()
        }
    }

    // MARK: Wake-light sheet

    @Test(arguments: WakeLightSheet.Tab.allCases)
    func wakeLightSheetTabsRender(tab: WakeLightSheet.Tab) async {
        for scenario in BedroomFixtures.Scenario.allCases {
            let hosted = await show(WakeLightSheet(devices: devices(scenario), initialTab: tab))
            hosted.close()
        }
        let admin = await show(WakeLightSheet(devices: devices(.waking), initialTab: tab), typeSize: .accessibility5)
        admin.close()
        let viewer = await show(WakeLightSheet(devices: devices(.default, canEdit: false), initialTab: tab))
        viewer.close()
    }

    @Test func wakeLightSheetNoticesCoverOldIntegrationsBlockersAndErrors() async {
        func status(_ devices: BedroomDevices, _ change: @escaping (inout EntityState) -> Void) {
            setState(devices, MasterBedroom.wakeLight.statusEntityId, change)
        }
        let old = devices(.default) { _ in }
        status(old) { $0.attributes["contract_version"] = .number(3) }
        let incompatible = await show(WakeLightSheet(devices: old, initialTab: .defaults))
        incompatible.close()
        let v5 = devices(.default) { _ in }
        status(v5) { $0.attributes["contract_version"] = .number(5) }
        let holdUnsupported = await show(WakeLightSheet(devices: v5, initialTab: .defaults))
        holdUnsupported.close()
        let down = devices(.default) { _ in }
        status(down) { $0.attributes["command_available"] = false }
        let unavailable = await show(WakeLightSheet(devices: down, initialTab: .alarms))
        unavailable.close()
        let blocked = devices(.waking) { _ in }
        status(blocked) { $0.attributes["current_blockers"] = ["pbl_not_ready", "source_missing"] }
        let blockers = await show(WakeLightSheet(devices: blocked, initialTab: .alarms))
        blockers.close()
        let empty = devices(.default) { _ in }
        status(empty) { $0.attributes["alarms"] = .array([]) }
        let none = await show(WakeLightSheet(devices: empty, initialTab: .alarms))
        none.close()

        let caller = ScriptedCaller()
        caller.fail = true
        let failing = devices(.waking, caller: caller)
        let hosted = await show(WakeLightSheet(devices: failing, initialTab: .alarms))
        let before = hosted.fingerprint
        #expect(await failing.wakeLight.endEpisode() == false)
        #expect(failing.wakeLight.error != nil)
        await hosted.settle()
        #expect(hosted.fingerprint != before)
        hosted.close()
    }

    @Test func wakeLightEditorsRenderEveryKind() async {
        let devices = devices(.default) { _ in }
        setState(devices, MasterBedroom.wakeLight.statusEntityId) { entity in
            guard case var .array(alarms)? = entity.attributes["alarms"] else { return }
            alarms.append(.object(["id": "once", "label": "Flight", "kind": "once", "local_time": "05:00", "date": "2031-02-03",
                                   "enabled": true, "ramp_minutes": .number(15), "revision": .number(1)]))
            entity.attributes["alarms"] = .array(alarms)
        }
        for id in [nil, "weekday", "weekend", "once"] as [String?] {
            let editor = await show(NavigationStack { WakeLightEditor(devices: devices, alarmId: id) {} })
            editor.close()
        }
        let large = await show(NavigationStack { WakeLightEditor(devices: devices, alarmId: "once") {} }, typeSize: .accessibility5)
        large.close()
        let viewer = self.devices(.default, canEdit: false)
        let readOnly = await show(NavigationStack { WakeLightEditor(devices: viewer, alarmId: "weekday") {} })
        readOnly.close()
        let old = self.devices(.default) { _ in }
        setState(old, MasterBedroom.wakeLight.statusEntityId) { $0.attributes["contract_version"] = .number(4) }
        let oneTimeUnsupported = await show(NavigationStack { WakeLightEditor(devices: old, alarmId: nil) {} })
        oneTimeUnsupported.close()
    }

    @Test func editorOffersTheLatestAlarmAfterARevisionConflict() async {
        let caller = ScriptedCaller()
        caller.responses = [.object(["outcome": "rejected", "error_code": "revision_conflict", "conflict": "alarm_revision", "revision": .number(13)])]
        let devices = devices(.default, caller: caller)
        let editor = await show(NavigationStack { WakeLightEditor(devices: devices, alarmId: "weekday") {} })
        let before = editor.fingerprint
        var alarm = devices.wakeLight.snapshot.alarms[0]
        alarm.label = "Changed"
        #expect(await devices.wakeLight.save(alarm) == false)
        #expect(devices.wakeLight.requiresAlarmReload)
        await editor.settle(rounds: 5)
        #expect(editor.fingerprint != before)
        editor.close()
    }

    // MARK: Gallery

    @Test(arguments: ["wake-light", "stephens-bed", "stephs-bed"])
    func galleryOpensEachSheet(sheet: String) async {
        for scenario in ["default", "solo-trip"] {
            setenv("FENTON_GALLERY_SHEET", sheet, 1)
            setenv("FENTON_GALLERY_TAB", sheet == "wake-light" ? "defaults" : "alarms", 1)
            setenv("FENTON_GALLERY_SCENARIO", scenario, 1)
            let hosted = await show(NavigationStack { BedroomGallery() })
            unsetenv("FENTON_GALLERY_SHEET")
            unsetenv("FENTON_GALLERY_TAB")
            unsetenv("FENTON_GALLERY_SCENARIO")
            hosted.close()
        }
    }

    @Test func galleryShowsTheTilesAndTheLastCall() async {
        unsetenv("FENTON_GALLERY_SHEET")
        let hosted = await show(NavigationStack { BedroomGallery() }, typeSize: .accessibility3)
        hosted.close()
        let page = await show(NavigationStack { ComponentGallery(page: .bedroom) })
        page.close()
    }

    // MARK: Shared components

    @Test func clockTimeFieldRoundTripsTimes() {
        let date = ClockTimeField.date("06:45")
        #expect(Calendar.current.component(.hour, from: date) == 6 && Calendar.current.component(.minute, from: date) == 45)
        #expect(ClockTimeField.string(date) == "06:45")
        #expect(ClockTimeField.string(ClockTimeField.date("23:05")) == "23:05")
        // A malformed time falls back to 07:00.
        #expect(ClockTimeField.string(ClockTimeField.date("")) == "07:00")
    }

    @Test func sharedComponentsRender() async {
        var days: [Weekday] = [.monday]
        var ramp = 15
        let components = VStack {
            BedroomNotice(title: "Title", message: "Info", tone: .info)
            BedroomNotice(message: "Warning")
            BedroomNotice(message: "Error", tone: .error)
            BedroomNotice(message: "Success", tone: .success)
            WeekdayPicker(title: "Days", days: Binding(get: { days }, set: { days = $0 }), identifier: "d")
            ChoiceGrid(title: "Ramp", options: [0, 15, 30], label: { "\($0)" }, selection: Binding(get: { ramp }, set: { ramp = $0 }),
                       isDisabled: true, identifier: "r")
            BedroomSectionHeader(title: "Header", detail: "Detail")
            BedroomRow(symbol: "alarm", title: "Row", lines: ["a", "b"], isMuted: true) { Text("x") }
        }
        let normal = await show(components)
        normal.close()
        let large = await show(components, typeSize: .accessibility5)
        large.close()
        let tabs = await show(BedroomTabPicker(label: "Tabs", tabs: WakeLightSheet.Tab.allCases, title: \.title,
                                               selection: .constant(.alarms), identifier: "t"), typeSize: .accessibility5)
        tabs.close()
    }
}
