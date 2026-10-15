import Foundation
@testable import HassCore
import Testing

/// A fix `meters` due north of (47.6, -122.3), where one degree of latitude is about 111.2 km.
func fixNorth(of meters: Double, accuracy: Double = 10, at time: TimeInterval = 0) -> LocationFix {
    LocationFix(latitude: 47.6 + meters / 111_195, longitude: -122.3, horizontalAccuracy: accuracy,
                timestamp: Date(timeIntervalSince1970: 1_000_000 + time))
}

let homeZone = HAZone(entityID: "zone.home", latitude: 47.6, longitude: -122.3, radius: 40, friendlyName: "Home")

/// A zone `meters` north of home.
func zone(_ id: String, north meters: Double, radius: Double = 150, passive: Bool = false) -> HAZone {
    HAZone(entityID: "zone.\(id)", latitude: 47.6 + meters / 111_195, longitude: -122.3, radius: radius,
           isPassive: passive, friendlyName: id.capitalized)
}

@Suite("Location fix")
struct LocationFixTests {
    @Test func distanceMatchesTheMeasuredSpacing() {
        let home = fixNorth(of: 0)
        #expect(abs(home.distance(to: fixNorth(of: 1000)) - 1000) < 1)
        // Seattle to Portland is about 233 km.
        let portland = LocationFix(latitude: 45.5152, longitude: -122.6784, horizontalAccuracy: 5)
        #expect(abs(home.distance(to: portland) / 1000 - 233) < 3)
    }

    @Test func validity() {
        #expect(fixNorth(of: 0).isValid)
        #expect(!LocationFix(latitude: 0, longitude: 0, horizontalAccuracy: -1).isValid)
        #expect(!LocationFix(latitude: -91, longitude: 0, horizontalAccuracy: 1).isValid)
        #expect(!LocationFix(latitude: 0, longitude: -181, horizontalAccuracy: 1).isValid)
    }

    @Test func zoneDistanceIsFromTheEdge() {
        #expect(abs(homeZone.distanceOutside(fixNorth(of: 100)) - 60) < 1)
        #expect(homeZone.distanceOutside(fixNorth(of: 0)) < 0)
        #expect(homeZone.isHome && !zone("work", north: 1).isHome)
    }
}

@Suite("Zone planner")
struct ZonePlannerTests {
    @Test func homeAlwaysPassiveNeverNearestFirst() {
        let zones = [zone("far", north: 9000), zone("gym", north: 500, passive: true), homeZone,
                     zone("near", north: 2000), zone("mid", north: 5000)]
        let plan = ZonePlanner(limit: 3).plan(zones, near: fixNorth(of: 3000))
        #expect(plan.map(\.id) == ["zone.home", "zone.near", "zone.mid"])
    }

    @Test func homeIsKeptEvenWhenFarAway() {
        let zones = (1...25).map { zone("z\($0)", north: Double($0) * 1000) } + [homeZone]
        let plan = ZonePlanner().plan(zones, near: fixNorth(of: 25_000))
        #expect(plan.count == ZonePlanner.regionLimit)
        #expect(plan.first?.id == "zone.home")
        #expect(plan.dropFirst().first?.id == "zone.z25")
        #expect(!plan.contains { $0.id == "zone.z1" }, "The farthest zones are left out")
    }

    @Test func smallZonesArePaddedTo100Meters() {
        let plan = ZonePlanner().plan([homeZone, zone("big", north: 1000, radius: 300)], near: nil)
        #expect(plan == [
            PlannedRegion(id: "zone.home", latitude: 47.6, longitude: -122.3, radius: 100),
            PlannedRegion(id: "zone.big", latitude: 47.6 + 1000 / 111_195, longitude: -122.3, radius: 300),
        ])
    }

    @Test func withoutAFixHomeAssistantsOrderIsKept() {
        let zones = [zone("b", north: 9000), zone("a", north: 10), zone("c", north: 5)]
        #expect(ZonePlanner(limit: 2).plan(zones, near: nil).map(\.id) == ["zone.b", "zone.a"])
        #expect(ZonePlanner(limit: 2).plan(zones, near: LocationFix(latitude: 0, longitude: 0, horizontalAccuracy: -1))
            .map(\.id) == ["zone.b", "zone.a"], "An invalid fix is no fix")
    }

    @Test func equalDistancesKeepTheirOrder() {
        let zones = [zone("first", north: 1000), zone("second", north: 1000)]
        #expect(ZonePlanner().plan(zones, near: fixNorth(of: 0)).map(\.id) == ["zone.first", "zone.second"])
    }

    @Test func zeroLimitPlansNothing() {
        #expect(ZonePlanner(limit: 0).plan([homeZone], near: nil).isEmpty)
        #expect(ZonePlanner(limit: 1).plan([homeZone, zone("x", north: 1)], near: nil).map(\.id) == ["zone.home"])
    }
}

@Suite("Zone event resolver")
struct ZoneEventResolverTests {
    let resolver = ZoneEventResolver(zones: [homeZone, zone("work", north: 5000), zone("mall", north: 300, radius: 50, passive: true)])

    @Test func enteringNamesTheZone() {
        #expect(resolver.locationName(for: .entered("zone.home"), fix: nil) == "home")
        #expect(resolver.locationName(for: .entered("zone.work"), fix: nil) == "Work")
        #expect(resolver.locationName(for: .entered("zone.mall"), fix: nil) == nil, "Passive zones never name a state")
        #expect(resolver.locationName(for: .entered("zone.unknown"), fix: nil) == nil)
    }

    @Test func exitingSaysNotHomeOnlyWhenClearOfEveryZone() {
        #expect(resolver.locationName(for: .exited("zone.home"), fix: fixNorth(of: 1000, accuracy: 20)) == "not_home")
        // 60 m outside home's edge, but only 65 m accurate: it might still be home.
        #expect(resolver.locationName(for: .exited("zone.home"), fix: fixNorth(of: 100, accuracy: 65)) == nil)
        // Inside work.
        #expect(resolver.locationName(for: .exited("zone.home"), fix: fixNorth(of: 5050)) == nil)
        // Inside the passive mall only: still not_home.
        #expect(resolver.locationName(for: .exited("zone.home"), fix: fixNorth(of: 300, accuracy: 5)) == "not_home")
        #expect(resolver.locationName(for: .exited("zone.home"), fix: nil) == nil)
        #expect(resolver.locationName(for: .exited("zone.home"), fix: LocationFix(latitude: 0, longitude: 0, horizontalAccuracy: -1)) == nil)
    }

    @Test func eventsCarryTheirTrigger() {
        #expect(ZoneEvent.entered("zone.home").trigger == .regionEntered)
        #expect(ZoneEvent.exited("zone.home").trigger == .regionExited)
    }
}

/// Holds a filter so `#expect` can call its mutating `admit` through a reference.
final class FilterBox {
    var filter = LocationFixFilter()
    var lastAdmitted: LocationFix? { filter.lastAdmitted }
    func admit(_ fix: LocationFix, trigger: LocationTrigger) -> Bool { filter.admit(fix, trigger: trigger) }
    func reset() { filter.reset() }
}

@Suite("Location fix filter")
struct LocationFixFilterTests {
    @Test func inaccurateFixesAreDroppedUnlessAZoneEventCausedThem() {
        let filter = FilterBox()
        #expect(!filter.admit(fixNorth(of: 0, accuracy: 201), trigger: .significantLocationChange))
        #expect(filter.lastAdmitted == nil)
        #expect(filter.admit(fixNorth(of: 0, accuracy: 200), trigger: .launch))
        #expect(filter.admit(fixNorth(of: 0, accuracy: 900, at: 1), trigger: .regionExited))
        #expect(filter.admit(fixNorth(of: 0, accuracy: 900, at: 2), trigger: .regionEntered))
    }

    @Test func duplicatesWithin30SecondsAnd10MetersAreDropped() {
        let filter = FilterBox()
        #expect(filter.admit(fixNorth(of: 0), trigger: .launch))
        #expect(!filter.admit(fixNorth(of: 5, at: 10), trigger: .significantLocationChange))
        #expect(!filter.admit(fixNorth(of: 5, at: 10), trigger: .pushNotification))
        #expect(filter.admit(fixNorth(of: 5, at: 10), trigger: .manual), "Asked for: always sent")
        #expect(filter.admit(fixNorth(of: 30, at: 15), trigger: .significantLocationChange), "Moved")
        #expect(filter.admit(fixNorth(of: 30, at: 50), trigger: .backgroundFetch), "Later")
    }

    @Test func invalidFixesNeverPass() {
        let filter = FilterBox()
        #expect(!filter.admit(LocationFix(latitude: 0, longitude: 0, horizontalAccuracy: -1), trigger: .regionEntered))
    }

    @Test func resetForgetsTheLastFix() {
        let filter = FilterBox()
        #expect(filter.admit(fixNorth(of: 0), trigger: .launch))
        filter.reset()
        #expect(filter.admit(fixNorth(of: 0, at: 1), trigger: .launch))
    }

    @Test func triggersUseTheOfficialAppsStrings() {
        #expect(LocationTrigger.allCases.map(\.rawValue) == [
            "Launch", "Geographic Region Entered", "Geographic Region Exited", "Significant Location Change",
            "Background Fetch", "Push Notification", "Manual",
        ])
        #expect(LocationTrigger.allCases.filter(\.isZoneEvent) == [.regionEntered, .regionExited])
    }
}
