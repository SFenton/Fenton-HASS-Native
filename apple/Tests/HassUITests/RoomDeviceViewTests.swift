import Foundation
import HassCore
import HassDesign
@testable import HassUI
import SwiftUI
import Testing

/// Hosted renders of the room device sheets on phone and tablet sizes and at AX5, plus their pure UI mappings.
@MainActor
struct RoomDeviceViewTests {
    static let phone = CGSize(width: 402, height: 874)
    static let tabletLandscape = CGSize(width: 1210, height: 834)

    func render<V: View>(_ view: V, size: CGSize = phone, typeSize: DynamicTypeSize = .large) -> CGImage? {
        let renderer = ImageRenderer(content: view.dynamicTypeSize(typeSize).frame(width: size.width, height: size.height))
        renderer.proposedSize = ProposedViewSize(size)
        return renderer.cgImage
    }

    func fixture(_ id: String) -> RoomDeviceFixture { RoomDeviceFixture.all().first { $0.id == id }! }

    func humidifier(_ id: String = "humidifier") -> (HumidifierController, HumidifierScheduleController) {
        let store = fixture(id).store
        return (HumidifierController(config: .masterBedroom, store: store, caller: NullCaller()),
                HumidifierScheduleController(config: .masterBedroom, store: store, caller: NullCaller(), storage: GalleryScheduleStore()))
    }

    // MARK: Renders

    @Test(arguments: [DynamicTypeSize.large, .accessibility5])
    func everySheetRenders(typeSize: DynamicTypeSize) {
        for fixture in RoomDeviceFixture.all() {
            let caller = NullCaller()
            let view: AnyView = switch fixture.kind {
            case let .fan(config): AnyView(BathroomFanSheet(config: config, store: fixture.store, caller: caller))
            case let .purifier(config): AnyView(AirPurifierSheet(config: config, store: fixture.store, caller: caller))
            case .grill: AnyView(GrillSheet(store: fixture.store, caller: caller))
            case .humidifier: AnyView(HumidifierSheet(config: .masterBedroom, store: fixture.store, caller: caller, storage: GalleryScheduleStore()))
            }
            #expect(render(view, typeSize: typeSize) != nil, "\(fixture.id)")
        }
    }

    @Test(arguments: HumidifierTab.allCases)
    func humidifierTabsRenderInBothLayouts(tab: HumidifierTab) async {
        let (controller, schedules) = humidifier()
        await schedules.load()
        #expect(render(HumidifierSheet(controller: controller, schedules: schedules, initialTab: tab)) != nil)
        #expect(render(HumidifierSheet(controller: controller, schedules: schedules, initialTab: tab,
                                       window: WindowMetrics(size: Self.tabletLandscape, isRegularWidth: true)),
                       size: Self.tabletLandscape) != nil)
        #expect(render(HumidifierSchedulesTab(schedules: schedules, onEdit: { _ in }, onAdd: {})) != nil)
    }

    @Test func controlsRenderWithEverythingUnavailable() {
        let store = EntityStore()
        let caller = NullCaller()
        #expect(render(BathroomFanControls(controller: BathroomFanController(config: .guest, store: store, caller: caller))) != nil)
        #expect(render(AirPurifierControls(controller: AirPurifierController(config: AirPurifierConfig.all[0], store: store, caller: caller))) != nil)
        #expect(render(GrillControls(controller: GrillController(store: store, caller: caller))) != nil)
        let humidifier = HumidifierController(config: .masterBedroom, store: store, caller: caller)
        #expect(render(HumidifierHero(controller: humidifier)) != nil)
        #expect(render(HumidifierControlsTab(controller: humidifier)) != nil)
        #expect(render(HumidifierInfoTab(controller: humidifier)) != nil)
    }

    @Test func activityEditorRendersNewAndExistingActivities() async {
        let (_, schedules) = humidifier()
        await schedules.load()
        for rule in [HumidifierScheduleRule.new(id: "new", mode: .targetHumidity), schedules.rules[0]] {
            let editor = NavigationStack {
                HumidifierActivityEditor(schedules: schedules, rule: rule, isNew: rule.id == "new") {}
            }
            #expect(render(editor) != nil)
            #expect(render(editor, typeSize: .accessibility5) != nil)
        }
        var empty = HumidifierScheduleRule.new(id: "bad")
        empty.days = []
        empty.start = "99"
        #expect(render(NavigationStack { HumidifierActivityEditor(schedules: schedules, rule: empty, isNew: true) {} }) != nil)
    }

    // MARK: Dial mapping

    @Test func mistDialShowsTheLevelOffOrSleep() {
        let (on, _) = humidifier()
        let dial = HumidifierDials.mist(on)
        #expect(dial.min == 0 && dial.max == 9 && dial.step == 1)
        #expect(dial.targets == .single(5))
        #expect(dial.current == 5)
        #expect(dial.primaryText(for: .single(7)) == "7", "Follows a drag")
        #expect(dial.caption(for: nil) == "Level 5 • 41% current")
        #expect(dial.acceptsInput)
        #expect(dial.accessibilityLabel(for: .target) == "Mist level")
        #expect(dial.readoutAccessibilityLabel == "Humidifier mist level 5, output level 5")

        let store = fixture("humidifier").store
        set(store, HumidifierConfig.masterBedroom.powerEntityId, "off")
        let off = HumidifierDials.mist(HumidifierController(config: .masterBedroom, store: store, caller: NullCaller()))
        #expect(off.primaryText(for: .single(0)) == "Off")
        #expect(off.targets == .single(0))
        #expect(off.caption(for: nil) == nil)
        #expect(off.isInactive)

        set(store, HumidifierConfig.masterBedroom.powerEntityId, "on")
        set(store, HumidifierConfig.masterBedroom.modeEntityId, "Sleep")
        let sleep = HumidifierDials.mist(HumidifierController(config: .masterBedroom, store: store, caller: NullCaller()))
        #expect(sleep.primaryText(for: .single(5)) == "Sleep")
        #expect(!sleep.acceptsInput)

        set(store, HumidifierConfig.masterBedroom.mistLevelEntityId, "unknown")
        set(store, HumidifierConfig.masterBedroom.modeEntityId, "Manual")
        let noLevel = HumidifierDials.mist(HumidifierController(config: .masterBedroom, store: store, caller: NullCaller()))
        #expect(noLevel.caption(for: nil) == "41% current")
    }

    @Test func faultMakesTheMistDialReadOnly() {
        let (fault, _) = humidifier("humidifier-fault")
        let dial = HumidifierDials.mist(fault)
        #expect(!dial.acceptsInput)
        #expect(dial.current == nil)
        #expect(!HumidifierDials.target(fault).acceptsInput)
    }

    @Test func targetDialsUseTheHumidityRangeAndTrails() {
        let (on, _) = humidifier()
        let target = HumidifierDials.target(on)
        #expect(target.min == 40 && target.max == 80 && target.step == 5)
        #expect(target.current == 41)
        #expect(target.primaryText(for: .single(55)) == "55")
        #expect(target.primaryUnit == "%")
        #expect(target.valueStyle?.trails.map(\.id) == ["comfort", "high"])
        #expect(target.spokenValue(55) == "55 percent")
        #expect(HumidifierDials.scheduledTarget(45).caption(for: nil) == nil)
        let mist = HumidifierDials.scheduledMist(3)
        #expect(mist.min == 1 && mist.targets == .single(3))
        #expect(mist.accessibilityLabel(for: .target) == "Scheduled mist level")
        #expect(mist.primaryUnit == nil)
    }

    // MARK: Pure helpers

    @Test func humidifierSplitsOnlyWhereAllowed() {
        #expect(HumidifierLayout.usesTwoColumns(window: Self.tabletLandscape, isRegularWidth: true, container: CGSize(width: 900, height: 700)))
        #expect(!HumidifierLayout.usesTwoColumns(window: Self.tabletLandscape, isRegularWidth: true, container: CGSize(width: 600, height: 700)))
        #expect(!HumidifierLayout.usesTwoColumns(window: CGSize(width: 834, height: 1210), isRegularWidth: true, container: CGSize(width: 800, height: 1000)))
        #expect(!HumidifierLayout.usesTwoColumns(window: Self.phone, isRegularWidth: false, container: Self.phone))
        #expect(HumidifierTab.allCases.map(\.title) == ["Controls", "Schedules", "Info"])
    }

    @Test func activityTimesConvertBothWays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let date = ActivityTime.date(from: "22:15", calendar: calendar)
        #expect(ActivityTime.string(from: date, calendar: calendar) == "22:15")
        #expect(ActivityTime.string(from: ActivityTime.date(from: "24:00", calendar: calendar), calendar: calendar) == "23:00")
        #expect(ActivityTime.string(from: ActivityTime.date(from: "junk", calendar: calendar), calendar: calendar) == "00:00")
    }

    @Test func spokenFanTimer() {
        #expect(BathroomFanControls.spokenRemaining(65).contains("1 minute"))
        #expect(DeviceStatusPill.color(.danger) == .red)
        #expect(DeviceStatusPill.color(.warning) == .orange)
        #expect(DeviceStatusPill.color(.ok) == .green)
    }

    // MARK: Gallery

    @Test func galleryEchoesCommandsIntoTheFixture() {
        let fan = fixture("fan-guest").store
        let guest = BathroomFanConfig.guest
        RoomDeviceGalleryEcho.apply("script", guest.scriptService, ["command": "power", "target_power": "on"], to: fan)
        #expect(fan.value(guest.powerEntityId)?.state == "on")
        RoomDeviceGalleryEcho.apply("script", guest.scriptService, ["command": "lock", "locked": true], to: fan)
        #expect(fan.value(guest.lockEntityId)?.state == "on")
        RoomDeviceGalleryEcho.apply("script", guest.scriptService, ["command": "timer_start", "minutes": 5, "auto_unlock": true], to: fan)
        #expect(fan.value(guest.pendingEntityId)?.state == "on")
        #expect(fan.value(guest.autoUnlockEntityId)?.state == "on")
        RoomDeviceGalleryEcho.apply("script", guest.scriptService, ["command": "timer_auto_unlock", "enabled": false], to: fan)
        #expect(fan.value(guest.autoUnlockEntityId)?.state == "off")
        RoomDeviceGalleryEcho.apply("script", guest.scriptService, ["command": "timer_cancel"], to: fan)
        #expect(fan.value(guest.pendingEntityId)?.state == "off")

        let h = HumidifierConfig.masterBedroom
        let humidifier = fixture("humidifier").store
        RoomDeviceGalleryEcho.apply("script", h.setLevelScriptService, ["level": 0], to: humidifier)
        #expect(humidifier.value(h.powerEntityId)?.state == "off")
        RoomDeviceGalleryEcho.apply("script", h.applyProfileScriptService, ["mode": "Sleep"], to: humidifier)
        #expect(humidifier.value(h.modeEntityId)?.state == "Sleep")
        RoomDeviceGalleryEcho.apply("number", "set_value", ["entity_id": h.warmLevelEntityId, "value": 3], to: humidifier)
        #expect(humidifier.value(h.warmLevelEntityId)?.state == "3.0")
        RoomDeviceGalleryEcho.apply("input_boolean", "turn_off", ["entity_id": h.scheduleEnabledEntityId], to: humidifier)
        #expect(humidifier.value(h.scheduleEnabledEntityId)?.state == "off")

        let purifier = fixture("purifier-manual").store
        let living = AirPurifierConfig.all[0]
        RoomDeviceGalleryEcho.apply("fan", "set_percentage", ["entity_id": living.fanEntityId, "percentage": 0], to: purifier)
        #expect(purifier.value(living.fanEntityId)?.state == "off")
        RoomDeviceGalleryEcho.apply("select", "select_option", ["entity_id": living.modeEntityId, "option": "Auto"], to: purifier)
        #expect(purifier.value(living.modeEntityId)?.state == "Auto")
    }

    @Test func galleryScheduleStoreSavesUpdates() async throws {
        let store = GalleryScheduleStore()
        let schedule = try #require(try await store.listSchedules().first)
        #expect(HumidifierSchedule.rules(from: schedule).count == 2)
        let saved = try await store.updateSchedule(HumidifierSchedule.updateMessage(schedule, rules: []))
        #expect(saved.id == HumidifierConfig.masterBedroom.scheduleId)
        #expect(HumidifierSchedule.rules(from: saved).isEmpty)
        #expect(try await store.userIsAdmin())
    }
}

private func set(_ store: EntityStore, _ id: String, _ state: String) {
    MainActor.assumeIsolated {
        var entity = store.value(id) ?? EntityState(entityId: id, state: state)
        entity.state = state
        store.apply([entity])
    }
}
