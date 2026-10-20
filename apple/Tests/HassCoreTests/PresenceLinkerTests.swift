import Foundation
@testable import HassCore
import Testing

/// A scripted websocket: answers by command type and records every command.
@MainActor
final class StubCommandAPI: HassCommandSending {
    var answers: [String: JSONValue] = [:]
    var failing: Set<String> = []
    private(set) var sent: [(type: String, data: [String: any Sendable])] = []

    func command(_ type: String, data: [String: any Sendable]) async throws -> JSONValue {
        sent.append((type, data))
        if failing.contains(type) { throw CancellationError() }
        return answers[type] ?? .null
    }

    var types: [String] { sent.map(\.type) }
}

@MainActor
struct PresenceLinkerTests {
    private let admin = HassUser(id: "u1", name: "Stephen", isOwner: false, isAdmin: true)

    private func api(trackers: [String] = ["device_tracker.iphone_18_pro"], disabled: String? = nil,
                     person: Bool = true) -> StubCommandAPI {
        let api = StubCommandAPI()
        api.answers["config/entity_registry/list"] = .array([
            .object(["platform": .string("mobile_app"), "unique_id": .string("w1"), "entity_id": .string("device_tracker.iphone_fenton"),
                     "disabled_by": disabled.map(JSONValue.string) ?? .null]),
            .object(["platform": .string("mobile_app"), "unique_id": .string("w1"), "entity_id": .string("sensor.iphone_fenton_battery")]),
            .object(["platform": .string("mobile_app"), "unique_id": .string("other"), "entity_id": .string("device_tracker.other")]),
        ])
        api.answers["person/list"] = .object(["storage": .array(person ? [
            .object(["id": .string("p0"), "name": .string("Stephanie"), "user_id": .string("u2"), "device_trackers": .array([])]),
            .object(["id": .string("p1"), "name": .string("Stephen"), "user_id": .string("u1"),
                     "device_trackers": .array(trackers.map(JSONValue.string))]),
        ] : []), "config": .array([])])
        return api
    }

    @Test func appendsTheTrackerKeepingTheOthers() async {
        let api = api()
        let outcome = await PresenceLinker.link(webhookID: "w1", user: admin, api: api)
        #expect(outcome == .linked(person: "Stephen"))
        let update = api.sent.last
        #expect(update?.type == "person/update")
        #expect(update?.data["person_id"] as? String == "p1")
        #expect(update?.data["device_trackers"] as? [String] == ["device_tracker.iphone_18_pro", "device_tracker.iphone_fenton"])
        #expect(update?.data.keys.sorted() == ["device_trackers", "person_id"], "nothing else on the person is sent")
        #expect(!api.types.contains("config/entity_registry/update"), "an enabled tracker is not touched")
    }

    @Test func isIdempotent() async {
        let api = api(trackers: ["device_tracker.iphone_fenton", "device_tracker.iphone_18_pro"])
        let outcome = await PresenceLinker.link(webhookID: "w1", user: admin, api: api)
        #expect(outcome == .alreadyLinked(person: "Stephen"))
        #expect(!api.types.contains("person/update"))
    }

    @Test func enablesADisabledTracker() async {
        let api = api(disabled: "integration")
        _ = await PresenceLinker.link(webhookID: "w1", user: admin, api: api)
        let enable = api.sent.first { $0.type == "config/entity_registry/update" }
        #expect(enable?.data["entity_id"] as? String == "device_tracker.iphone_fenton")
        #expect(enable?.data["disabled_by"] is NSNull)
    }

    @Test func nonAdminsDegradeWithoutSendingAnything() async {
        let api = api()
        let user = HassUser(id: "u1", name: nil, isOwner: false, isAdmin: false)
        #expect(await PresenceLinker.link(webhookID: "w1", user: user, api: api) == .needsAdmin)
        #expect(api.sent.isEmpty)
        let owner = HassUser(id: "u1", name: nil, isOwner: true, isAdmin: false)
        #expect(await PresenceLinker.link(webhookID: "w1", user: owner, api: api) == .linked(person: "Stephen"))
    }

    @Test func reportsAMissingPersonOrTracker() async {
        #expect(await PresenceLinker.link(webhookID: "w1", user: admin, api: api(person: false)) == .noPerson)
        #expect(await PresenceLinker.link(webhookID: "nope", user: admin, api: api()) == .trackerMissing)
        let empty = StubCommandAPI()
        #expect(await PresenceLinker.link(webhookID: "w1", user: admin, api: empty) == .trackerMissing)
    }

    @Test func failuresAreOutcomesNotCrashes() async {
        for type in ["config/entity_registry/list", "person/list", "person/update"] {
            let api = api()
            api.failing = [type]
            let outcome = await PresenceLinker.link(webhookID: "w1", user: admin, api: api)
            #expect(outcome == .failed, "\(type)")
            #expect(!outcome.isLinked)
        }
    }

    @Test func unlinkRemovesOnlyThisTracker() async throws {
        let api = api(trackers: ["device_tracker.iphone_18_pro", "device_tracker.iphone_fenton"])
        try await PresenceLinker.unlink(webhookID: "w1", user: admin, api: api)
        let update = api.sent.last
        #expect(update?.type == "person/update")
        #expect(update?.data["device_trackers"] as? [String] == ["device_tracker.iphone_18_pro"])
    }

    @Test func unlinkIsSuccessWhenAlreadyGone() async throws {
        let listed = api(trackers: ["device_tracker.iphone_18_pro"])
        try await PresenceLinker.unlink(webhookID: "w1", user: admin, api: listed)
        #expect(!listed.types.contains("person/update"), "not listed: nothing to do")
        try await PresenceLinker.unlink(webhookID: "nope", user: admin, api: api())
        try await PresenceLinker.unlink(webhookID: "w1", user: admin, api: api(person: false))
        let plain = HassUser(id: "u1", name: nil, isOwner: false, isAdmin: false)
        let untouched = api()
        try await PresenceLinker.unlink(webhookID: "w1", user: plain, api: untouched)
        #expect(untouched.sent.isEmpty)
    }

    @Test func unlinkFailuresThrow() async {
        for type in ["config/entity_registry/list", "person/list", "person/update"] {
            let api = api(trackers: ["device_tracker.iphone_fenton"])
            api.failing = [type]
            await #expect(throws: (any Error).self) { try await PresenceLinker.unlink(webhookID: "w1", user: admin, api: api) }
        }
    }
}
