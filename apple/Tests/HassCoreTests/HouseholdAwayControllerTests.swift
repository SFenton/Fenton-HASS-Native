import Foundation
@testable import HassCore
import Testing

/// Answers Household Away commands from a script and records what was sent.
@MainActor
final class ScriptedResponder: HassServiceResponding {
    var sent: [[String: any Sendable]] = []
    var responses: [Result<JSONValue, any Error>] = []
    /// Never answers (for timeouts).
    var hangs = false
    /// Runs after a command is recorded, before it answers (tests echo into the store here).
    var onCommand: (([String: any Sendable]) -> Void)?
    /// Answers only after this long (for late answers).
    var delay: Duration?

    struct Failure: Error {}

    static func accepted(revision: Int? = nil) -> Result<JSONValue, any Error> {
        var response: [String: JSONValue] = ["status": .string("accepted")]
        if let revision { response["revision"] = .number(Double(revision)) }
        return .success(.object(response))
    }

    func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {}

    func callServiceWithResponse(_ domain: String, _ service: String, data: [String: any Sendable]) async throws -> JSONValue {
        #expect(domain == "script")
        #expect(service == "household_away_command")
        sent.append(data)
        onCommand?(data)
        if let delay { try await Task.sleep(for: delay) }
        if hangs {
            try await Task.sleep(for: .seconds(60))
        }
        let next = responses.isEmpty ? Self.accepted() : responses.removeFirst()
        return try next.get()
    }

    func operation(_ index: Int) -> String? { sent[index]["operation"] as? String }
}

@MainActor
struct HouseholdAwayControllerTests {
    func make(_ entity: EntityState? = awayEntity(), timeout: Duration = .seconds(10)) -> (HouseholdAwayController, ScriptedResponder, EntityStore) {
        let store = EntityStore()
        if let entity { store.replaceAll([entity]) }
        let responder = ScriptedResponder()
        return (HouseholdAwayController(store: store, responder: responder, timeout: timeout, makeRequestId: { "req-1" }), responder, store)
    }

    @Test func acceptedCommandSendsRevisionAndRequestId() async {
        let (controller, responder, _) = make(awayEntity("idle", awayAttributes(revision: 5)))
        responder.responses = [ScriptedResponder.accepted(revision: 6)]
        let outcome = await controller.cancel()
        #expect(outcome == .accepted(revision: 6))
        #expect(controller.errorCode == nil)
        #expect(!controller.pending)
        #expect(responder.sent[0]["expected_revision"] as? Int == 5)
        #expect(responder.sent[0]["request_id"] as? String == "req-1")
        #expect(responder.operation(0) == "cancel")
        // The acknowledged revision is the floor for the next command even before the sensor catches up.
        await controller.endNow()
        #expect(responder.sent[1]["expected_revision"] as? Int == 6)
    }

    @Test func noChangeCountsAsAccepted() async {
        let (controller, responder, _) = make()
        responder.responses = [.success(.object(["response": .object(["outcome": .string("no_change")])]))]
        #expect(await controller.updateEnd(WallClock(date: "2026-10-12", time: "09:00")) == .accepted(revision: nil))
    }

    @Test func rejectionKeepsTheErrorCode() async {
        let (controller, responder, _) = make()
        responder.responses = [
            .success(.object(["status": .string("rejected"), "error_code": .string("stale_revision")])),
            .success(.object(["status": .string("rejected"), "error": .string("busy")])),
            .success(.object(["status": .string("blocked")])),
        ]
        #expect(await controller.resolveRestore(.keepCurrent) == .rejected(errorCode: "stale_revision"))
        #expect(controller.errorCode == "stale_revision")
        #expect(await controller.endNow() == .rejected(errorCode: "busy"))
        #expect(await controller.endNow() == .rejected(errorCode: "blocked"))
        controller.clearError()
        #expect(controller.errorCode == nil)
    }

    @Test func malformedOrFailedResponseIsTransport() async {
        let (controller, responder, _) = make()
        responder.responses = [.success(.object(["context": .null])), .success(.null), .failure(ScriptedResponder.Failure())]
        for _ in 0..<3 {
            #expect(await controller.cancel() == .rejected(errorCode: "transport"))
            #expect(controller.errorCode == "transport")
        }
    }

    @Test func unavailableSensorRefusesWithoutSending() async {
        let (controller, responder, _) = make(awayEntity("idle", awayAttributes(commandAvailable: false)))
        #expect(await controller.cancel() == .rejected(errorCode: "unavailable"))
        #expect(controller.errorCode == "unavailable")
        #expect(responder.sent.isEmpty)
    }

    @Test func timeoutIsUnknown() async {
        let (controller, responder, _) = make(timeout: .milliseconds(50))
        responder.hangs = true
        #expect(await controller.endNow() == .unknown)
        #expect(controller.errorCode == "unknown_outcome")
        #expect(!controller.pending)
    }

    @Test func oneCommandAtATime() async {
        let (controller, responder, _) = make(timeout: .milliseconds(200))
        responder.hangs = true
        async let first = controller.endNow()
        await Task.yield()
        #expect(controller.pending)
        #expect(await controller.cancel() == .rejected(errorCode: "transport"))
        #expect(await first == .unknown)
        #expect(responder.sent.count == 1)
    }

    @Test func scheduleSendsTheDraft() async {
        let (controller, responder, _) = make()
        let draft = SoloTripDraft(start: WallClock(date: "2026-10-12", time: "08:00"), end: WallClock(date: "2026-10-14", time: "18:00"))
        await controller.scheduleSoloTrip(traveler: .stephen, draft: draft)
        #expect(responder.sent[0]["traveler"] as? String == "stephen")
        #expect(responder.sent[0]["end_time"] as? String == "18:00")
    }

    @Test func snapshotFollowsTheStore() {
        let (controller, _, store) = make()
        #expect(controller.snapshot.mode == .none)
        store.apply([awayEntity("scheduled", awayAttributes(mode: "solo_trip", traveler: "steph"))])
        #expect(controller.snapshot.state == .scheduled)
    }

    @Test func aResponseThatIsNotAnObjectIsTransport() async {
        let (controller, responder, _) = make()
        responder.responses = [.success(.object(["response": .string("oops")]))]
        // The wrapper's own fields hold no status, and a non-object `response` is not unwrapped.
        #expect(await controller.cancel() == .rejected(errorCode: "transport"))
    }

    @Test func aWrappedResponseIsUnwrapped() async {
        let (controller, responder, _) = make()
        responder.responses = [.success(.object(["response": .object(["status": .string("accepted"), "revision": .number(9)])]))]
        #expect(await controller.cancel() == .accepted(revision: 9))
    }

    @Test func aFractionalRevisionIsIgnored() async {
        let (controller, responder, _) = make(awayEntity("idle", awayAttributes(revision: 5)))
        responder.responses = [.success(.object(["status": .string("accepted"), "revision": .number(6.5)]))]
        #expect(await controller.cancel() == .accepted(revision: nil))
        // The floor stays at the sensor's revision.
        await controller.endNow()
        #expect(responder.sent[1]["expected_revision"] as? Int == 5)
    }

    @Test func aLateAnswerAfterTheTimeoutIsDropped() async {
        let (controller, responder, _) = make(timeout: .milliseconds(20))
        responder.delay = .milliseconds(120)
        responder.responses = [ScriptedResponder.accepted(revision: 8)]
        #expect(await controller.endNow() == .unknown)
        // The answer arrives after the outcome was already reported unknown: it changes nothing.
        try? await Task.sleep(for: .milliseconds(250))
        #expect(controller.errorCode == "unknown_outcome")
        #expect(!controller.pending)
        responder.delay = nil
        responder.responses = [ScriptedResponder.accepted()]
        await controller.cancel()
        #expect(responder.sent[1]["expected_revision"] as? Int == 3)
    }

    @Test func theTimeoutFiringAfterAnAnswerIsIgnored() async {
        let (controller, _, _) = make(timeout: .milliseconds(60))
        #expect(await controller.cancel() == .accepted(revision: nil))
        try? await Task.sleep(for: .milliseconds(150))
        #expect(controller.errorCode == nil)
    }

    @Test func requestIdsAreUniqueByDefault() async {
        let store = EntityStore()
        store.replaceAll([awayEntity()])
        let responder = ScriptedResponder()
        let controller = HouseholdAwayController(store: store, responder: responder)
        await controller.cancel()
        await controller.cancel()
        let ids = responder.sent.compactMap { $0["request_id"] as? String }
        #expect(ids.count == 2)
        #expect(Set(ids).count == 2)
        #expect(ids.allSatisfy { $0 == $0.lowercased() && UUID(uuidString: $0) != nil })
        #expect(HouseholdAwayController.commandTimeout == .seconds(10))
    }
}
