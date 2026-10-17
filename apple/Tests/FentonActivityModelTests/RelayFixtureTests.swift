import Foundation
@testable import FentonActivityModel
import Testing

/// The relay's real output (`SFenton/ha-fenton-push` `tests/fixtures/live-*.apns`, mirrored in `tools/push_fixtures`):
/// the app decodes what Python wrote, with the same default `JSONDecoder` ActivityKit uses.
struct RelayFixtureTests {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func aps(_ name: String) throws -> [String: Any] {
        let data = try Data(contentsOf: Self.root.appendingPathComponent("tools/push_fixtures/\(name).apns"))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(object["aps"] as? [String: Any])
    }

    private func state(_ name: String) throws -> HomeActivityState {
        let content = try #require(aps(name)["content-state"])
        return try HomeActivityState.decode(JSONSerialization.data(withJSONObject: content))
    }

    @Test func theStartContentDecodesAndKeepsItsTimesIn2026() throws {
        let state = try state("live-start")
        #expect(state.jobs.map(\.id) == ["dishwasher", "fan.master"])
        #expect(state.focus == "dishwasher" && state.url == "/sfenton-react-dash/home?path=kitchen")
        let end = try #require(state.jobs[0].endDate)
        #expect(Calendar(identifier: .gregorian).component(.year, from: end) == 2026, "a Date read from 2001 would land in 1995")
        #expect(state.jobs[0].controls == [ActivityControl(id: "stop", title: "Stop", role: .destructive)])
        #expect(state.jobs[0].trailing != .none)
    }

    @Test func theStartCarriesAttributesTheAppDecodes() throws {
        let aps = try aps("live-start")
        #expect(aps["attributes-type"] as? String == HomeActivityAttributes.wireName)
        let attributes = try #require(aps["attributes"] as? [String: Any])
        let decoded = try JSONDecoder().decode(HomeActivityAttributes.self, from: JSONSerialization.data(withJSONObject: attributes))
        #expect(decoded == HomeActivityAttributes(tag: HomeActivityAttributes.homeTag, title: "Home", kind: "home"))
    }

    @Test func theEndFixtureIsAnEmptyListTheAppAccepts() throws {
        let state = try state("live-end")
        #expect(state.jobs.isEmpty && state.focusedJob == nil)
    }

    @Test func theGenericFixtureIsOneCountdownJob() throws {
        let state = try state("live-generic")
        let job = try #require(state.jobs.first)
        #expect(state.jobs.count == 1 && job.kind == "generic" && job.symbol == "drop.fill")
        #expect(job.timerRange != nil && job.progress == 0.25)
    }

    @Test func everyFixtureFitsApplesFourKilobytes() throws {
        for name in ["live-start", "live-update", "live-end", "live-generic"] {
            let data = try Data(contentsOf: Self.root.appendingPathComponent("tools/push_fixtures/\(name).apns"))
            let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let compact = try JSONSerialization.data(withJSONObject: object.filter { $0.key != "Simulator Target Bundle" })
            #expect(compact.count < HomeActivityState.maxPayloadBytes, Comment(rawValue: name))
        }
    }
}
