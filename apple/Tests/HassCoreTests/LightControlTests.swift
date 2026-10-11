@testable import HassCore
import Testing

struct LightControlTests {
    @Test func powerSendsExplicitServicesNeverToggle() {
        #expect(LightControl.power("light.gym_light", on: true) == .init(domain: "light", service: "turn_on", entityId: "light.gym_light"))
        #expect(LightControl.power("light.gym_light", on: false).service == "turn_off")
        #expect(LightControl.power("switch.upper_entryway_light_switch_top", on: true).domain == "switch")
        #expect(LightControl.power("scene.evening", on: true).domain == "homeassistant")
    }

    /// A bare `turn_on` with only `entity_id` is what Presence Lock honors as a manual on.
    @Test func turnOnCarriesOnlyTheEntity() {
        let data = LightControl.power("light.gym_light", on: true).serviceData
        #expect(data.count == 1)
        #expect(data["entity_id"] as? String == "light.gym_light")
    }

    @Test func flipUsesTheShownState() {
        #expect(LightControl.flip("light.kitchen", shownOn: true).service == "turn_off")
        #expect(LightControl.flip("light.kitchen", shownOn: false).service == "turn_on")
    }

    @Test func brightnessSetsPercentAndZeroTurnsOff() {
        let set = LightControl.brightness("light.office_light", percent: 42.6)
        #expect(set == .init(domain: "light", service: "turn_on", entityId: "light.office_light", brightnessPercent: 43))
        #expect(set.serviceData["brightness_pct"] as? Int == 43)
        #expect(LightControl.brightness("light.office_light", percent: 0) == LightControl.power("light.office_light", on: false))
        #expect(LightControl.brightness("light.office_light", percent: 0.4).service == "turn_off")
        #expect(LightControl.brightness("light.office_light", percent: 140).brightnessPercent == 100)
        #expect(LightControl.brightness("light.office_light", percent: .nan).service == "turn_off")
    }

    @Test func percentFollowsTheWeb() {
        #expect(LightControl.percent(of: nil) == 0)
        #expect(LightControl.percent(of: EntityState(entityId: "light.a", state: "off", attributes: ["brightness": .number(200)])) == 0)
        #expect(LightControl.percent(of: EntityState(entityId: "light.a", state: "on", attributes: ["brightness": .number(128)])) == 50)
        #expect(LightControl.percent(of: EntityState(entityId: "light.a", state: "on")) == 100)
        #expect(LightControl.percent(of: EntityState(entityId: "light.a", state: "on", attributes: ["brightness": .number(0)])) == 100)
        #expect(LightControl.percent(of: EntityState(entityId: "light.a", state: "unavailable")) == 0)
    }

    @Test func dimmableNeedsALightWithMoreThanOnOff() {
        let dimmable = EntityState(entityId: "light.a", state: "off", attributes: ["supported_color_modes": .array([.string("brightness")])])
        let onOff = EntityState(entityId: "light.b", state: "off", attributes: ["supported_color_modes": .array([.string("onoff")])])
        let lit = EntityState(entityId: "light.c", state: "on", attributes: ["brightness": .number(10)])
        #expect(LightControl.isDimmable(dimmable))
        #expect(!LightControl.isDimmable(onOff))
        #expect(LightControl.isDimmable(lit))
        #expect(!LightControl.isDimmable(EntityState(entityId: "switch.a", state: "on", attributes: ["brightness": .number(10)])))
        #expect(!LightControl.isDimmable(nil))
    }

    @Test func rgbReadsThreeNumbers() {
        let color = LightControl.rgb(of: EntityState(entityId: "light.a", state: "on", attributes: ["rgb_color": .array([.number(255), .number(0), .number(51)])]))
        #expect(color?.red == 1)
        #expect(color?.blue == 0.2)
        #expect(LightControl.rgb(of: EntityState(entityId: "light.a", state: "on", attributes: ["rgb_color": .array([.number(1)])])) == nil)
        #expect(LightControl.rgb(of: nil) == nil)
    }
}
