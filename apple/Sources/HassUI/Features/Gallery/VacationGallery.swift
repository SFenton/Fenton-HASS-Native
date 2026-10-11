import Foundation
import HassCore
import HassDesign
import Observation
import SwiftUI

/// Gallery page for Vacation and Solo Trip: the real screens on a fixture house that answers like Home
/// Assistant, so journeys can enable vacations and schedule trips without touching the real one.
/// `FENTON_GALLERY_AWAY=<scenario>` picks the starting state (``VacationFixtures/Scenario``).
struct VacationGallery: View {
    @State private var house: VacationGalleryHouse

    init() {
        let scenario = ProcessInfo.processInfo.environment["FENTON_GALLERY_AWAY"]
            .flatMap(VacationFixtures.Scenario.init(rawValue:)) ?? .idle
        _house = State(initialValue: VacationGalleryHouse(store: VacationFixtures.store(scenario)))
    }

    var body: some View {
        VacationScreen(store: house.store, responder: house, caller: house) { HouseholdResident.stephen.haUserId }
            .safeAreaInset(edge: .bottom) {
                // FENTON_GALLERY_CLEAN=1 (screenshots) leaves the debug line out.
                if !MediaRemoteGallery.isClean {
                    Text("Last call: \(house.lastCall)")
                        .font(.caption.monospaced())
                        .foregroundStyle(HassTokens.Ink.secondary)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                        .background(.bar)
                        .accessibilityIdentifier("gallery.lastCall")
                }
            }
    }
}

/// A fixture house: records calls, then echoes them into the store after a short delay like Home Assistant.
@MainActor
@Observable
final class VacationGalleryHouse: HassServiceCalling, HassServiceResponding {
    private(set) var lastCall = "None"
    let store: EntityStore
    @ObservationIgnored private let delay: Duration

    init(store: EntityStore, delay: Duration = .milliseconds(400)) {
        self.store = store
        self.delay = delay
    }

    func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {
        lastCall = GalleryServiceRecorder.describe(domain, service, data)
        try? await Task.sleep(for: delay)
        let target = data["entity_id"] as? String
        switch (domain, service) {
        case ("input_boolean", "turn_on"): if let target { set(target, "on") }
        case ("input_boolean", "turn_off"): if let target { set(target, "off") }
        case ("input_datetime", "set_datetime"):
            if let target, let date = data["date"] as? String, let time = data["time"] as? String { set(target, "\(date) \(time)") }
        default: break
        }
    }

    func callServiceWithResponse(_ domain: String, _ service: String, data: [String: any Sendable]) async throws -> JSONValue {
        lastCall = GalleryServiceRecorder.describe(domain, service, data)
        try? await Task.sleep(for: delay)
        let current = store.value(HouseholdAway.statusEntityId)
        var attributes = current?.attributes ?? VacationFixtures.idleAttributes
        var state = current?.state ?? "idle"
        let revision = Int(attributes["revision"]?.number ?? 0) + 1
        attributes["revision"] = .number(Double(revision))
        switch data["operation"] as? String {
        case "schedule":
            let traveler = HouseholdResident(rawValue: data["traveler"] as? String ?? "") ?? .stephen
            let start = WallClock(date: data["start_date"] as? String ?? "", time: data["start_time"] as? String ?? "")
            attributes["mode"] = .string("solo_trip")
            attributes["traveler"] = .string(traveler.rawValue)
            attributes["home_resident"] = .string(traveler.other.rawValue)
            attributes["starts_at"] = .string("\(start.date) \(start.time):00")
            attributes["ends_at"] = .string("\(data["end_date"] as? String ?? "") \(data["end_time"] as? String ?? ""):00")
            let started = (start.date(in: .current) ?? .distantFuture) <= .now
            state = started ? "active" : "scheduled"
            attributes["effects"] = VacationFixtures.effects(started)
        case "cancel", "end_now":
            attributes = VacationFixtures.idleAttributes
            attributes["revision"] = .number(Double(revision))
            state = "idle"
        case "update_end":
            attributes["ends_at"] = .string("\(data["end_date"] as? String ?? "") \(data["end_time"] as? String ?? ""):00")
        case "resolve_restore":
            state = "active"
        default:
            return .object(["status": .string("rejected"), "error_code": .string("unsupported_operation")])
        }
        store.apply([EntityState(entityId: HouseholdAway.statusEntityId, state: state, attributes: attributes)])
        return .object(["status": .string("accepted"), "revision": .number(Double(revision))])
    }

    private func set(_ id: String, _ state: String) {
        var entity = store.value(id) ?? EntityState(entityId: id, state: state)
        entity.state = state
        store.apply([entity])
    }
}

/// Synthetic states for the gallery and hosted tests (not a copy of the live house).
enum VacationFixtures {
    /// Starting states.
    enum Scenario: String, CaseIterable, Sendable {
        /// Nothing engaged, checklist empty.
        case idle
        /// Nothing engaged, checklist done.
        case ready
        /// Vacation Mode on with dates.
        case vacation
        /// Home Assistant paused the vacation: end before start.
        case invalidDates = "invalid-dates"
        /// Stephen away on a fully active Solo Trip.
        case soloActive = "solo-active"
        /// A Solo Trip scheduled for tomorrow.
        case soloScheduled = "solo-scheduled"
        /// A Solo Trip that needs a restore decision.
        case soloRestore = "solo-restore"
        /// The Household Away script isn't set up.
        case unavailable
    }

    static let idleAttributes: [String: JSONValue] = [
        "contract_version": .number(1),
        "command_available": .bool(true),
        "mode": .string("none"),
        "traveler": .string("none"),
        "home_resident": .string("none"),
        "revision": .number(3),
        "effects": effects(false),
        "blockers": .array([]),
    ]

    static func effects(_ on: Bool) -> JSONValue {
        .object(["sleepypod_live_follow": .bool(on), "sleepypod_schedule": .bool(on), "wake_light_source": .bool(on)])
    }

    @MainActor static func store(_ scenario: Scenario, now: Date = .now, calendar: Calendar = .current) -> EntityStore {
        let store = EntityStore()
        store.replaceAll(states(scenario, now: now, calendar: calendar), freshness: .live)
        return store
    }

    static func states(_ scenario: Scenario, now: Date = .now, calendar: Calendar = .current) -> [EntityState] {
        func stamp(_ days: Int, hour: Int = 9) -> String {
            let day = calendar.date(byAdding: .day, value: days, to: now) ?? now
            let wall = WallClock(calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day, calendar: calendar)
            return "\(wall.date) \(wall.time):00"
        }
        let checklistDone = scenario == .ready
        var states = [
            EntityState(entityId: Vacation.modeEntityId, state: scenario == .vacation ? "on" : "off"),
            EntityState(entityId: Vacation.invalidDatesPendingEntityId, state: scenario == .invalidDates ? "on" : "off"),
            EntityState(entityId: Vacation.startEntityId, state: scenario == .invalidDates ? stamp(5) : stamp(1)),
            EntityState(entityId: Vacation.endEntityId, state: scenario == .invalidDates ? stamp(2) : stamp(8)),
        ]
        states += Vacation.checklist.enumerated().map { index, item in
            EntityState(entityId: item.entityId, state: checklistDone || (scenario == .idle && index < 2) ? "on" : "off")
        }
        var attributes = idleAttributes
        var state = "idle"
        switch scenario {
        case .soloActive, .soloScheduled, .soloRestore:
            attributes["mode"] = .string("solo_trip")
            attributes["traveler"] = .string("stephen")
            attributes["home_resident"] = .string("steph")
            let scheduled = scenario == .soloScheduled
            attributes["starts_at"] = .string(scheduled ? stamp(1) : stamp(-1))
            attributes["ends_at"] = .string(stamp(4, hour: 18))
            attributes["effects"] = effects(scenario == .soloActive)
            state = scheduled ? "scheduled" : scenario == .soloRestore ? "restore_required" : "active"
        case .unavailable:
            attributes["command_available"] = .bool(false)
        default: break
        }
        states.append(EntityState(entityId: HouseholdAway.statusEntityId, state: state, attributes: attributes))
        return states
    }
}
