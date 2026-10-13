#if DEBUG
import HassCore
import HassDesign
import Observation
import SwiftUI

/// Gallery page for Security: the real page on fixture state with a recording service caller that echoes
/// doors, locks and alarm modes like Home Assistant, so journeys press real controls without touching the house.
/// Cameras are left out (they need a live connection); the hidden Vehicle section is shown so its tile is tested.
///
/// `FENTON_GALLERY_FAIL=1` makes every call fail (garage door error feedback); `FENTON_GALLERY_CLEAN=1` hides
/// the last-call line for screenshots.
struct SecurityGallery: View {
    @State private var store: EntityStore
    @State private var recorder: SecurityGalleryRecorder

    init() {
        let store = SecurityFixtures.store()
        _store = State(initialValue: store)
        _recorder = State(initialValue: SecurityGalleryRecorder(
            store: store, fails: ProcessInfo.processInfo.environment["FENTON_GALLERY_FAIL"] == "1"
        ))
    }

    var body: some View {
        SecurityPage(caller: recorder, canSend: true, showsCameras: false, showsVehicle: true)
            .environment(store)
            .safeAreaInset(edge: .bottom) {
                if ProcessInfo.processInfo.environment["FENTON_GALLERY_CLEAN"] != "1" {
                    Text("Last call: \(recorder.lastCall)")
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

/// Records calls and echoes them into the fixture store after short delays, like Home Assistant: a garage door
/// reports `opening` then `open`, locks and the alarm switch at once.
@MainActor
@Observable
final class SecurityGalleryRecorder: HassServiceCalling {
    private(set) var lastCall = "None"
    @ObservationIgnored private let store: EntityStore
    @ObservationIgnored private let fails: Bool

    struct Failure: Error {}

    init(store: EntityStore, fails: Bool) {
        self.store = store
        self.fails = fails
    }

    func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {
        lastCall = GalleryServiceRecorder.describe(domain, service, data)
        // A door's "Sending…" lasts until the call returns; hold it long enough for a journey to read it.
        try? await Task.sleep(for: domain == "cover" ? .seconds(2.5) : .milliseconds(300))
        if fails { throw Failure() }
        guard let target = data["entity_id"] as? String else { return }
        switch (domain, service) {
        case ("cover", "open_cover"): moveDoor(target, through: "opening", to: "open")
        case ("cover", "close_cover"): moveDoor(target, through: "closing", to: "closed")
        case ("lock", "lock"): set(target, "locked")
        case ("lock", "unlock"): set(target, "unlocked")
        case ("alarm_control_panel", _):
            if let mode = SecurityConfig.alarmModes.first(where: { $0.service == service }) { set(target, mode.state) }
        default: break
        }
    }

    private func moveDoor(_ id: String, through moving: String, to final: String) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1500))
            set(id, moving)
            try? await Task.sleep(for: .seconds(3))
            set(id, final)
        }
    }

    private func set(_ id: String, _ state: String) {
        var entity = store.value(id) ?? EntityState(entityId: id, state: state)
        entity.state = state
        store.apply([entity])
    }
}

/// Synthetic Security states for the gallery and hosted tests (not a copy of the live house).
enum SecurityFixtures {
    @MainActor static func store() -> EntityStore {
        let store = EntityStore()
        store.replaceAll(states, freshness: .live)
        return store
    }

    static let states: [EntityState] = [
        EntityState(entityId: SecurityConfig.alarmEntityId, state: "armed_home"),
        EntityState(entityId: SecurityConfig.frontDoorLockEntityId, state: "locked"),
        EntityState(entityId: SecurityConfig.leftGarageDoorEntityId, state: "closed"),
        EntityState(entityId: SecurityConfig.rightGarageDoorEntityId, state: "open"),
        EntityState(entityId: SecurityConfig.vehicleLockEntityId, state: "locked"),
        EntityState(entityId: SecurityConfig.contactSensorsEntityId, state: "on", attributes: [
            "entity_id": .array([.string("binary_sensor.front_door_contact"), .string("binary_sensor.back_door_contact")]),
        ]),
        EntityState(entityId: "binary_sensor.front_door_contact", state: "off", attributes: ["friendly_name": .string("Front Door")]),
        EntityState(entityId: "binary_sensor.back_door_contact", state: "on", attributes: ["friendly_name": .string("Back Door")]),
    ]
}
#endif
