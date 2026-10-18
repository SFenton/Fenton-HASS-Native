import Foundation

/// Fixture content for the debug gallery, the debug launch hook and tests: the same shapes the relay sends, with times
/// relative to `now` so a countdown is always ticking when it is drawn.
public enum HomeActivityFixtures {
    /// A named set of jobs.
    public enum Scenario: String, CaseIterable, Sendable {
        /// The dishwasher alone, 42 minutes left.
        case dishwasher
        /// A bathroom fan timer alone.
        case fan
        /// The dishwasher and a fan.
        case two
        /// The dishwasher and both fans, with a fan focused.
        case three
        /// Six jobs: the most the activity lists, with an estimated dryer and a job that reports progress.
        case six
        /// The dishwasher has finished (the linger).
        case done
        /// The dishwasher needs a person.
        case attention
        /// A control was pressed and Home Assistant has not confirmed it yet.
        case stopping
    }

    /// The content for a scenario.
    /// - Parameters:
    ///   - scenario: Which jobs.
    ///   - now: Where "42 minutes left" counts from.
    public static func state(_ scenario: Scenario, now: Date = Date()) -> HomeActivityState {
        let t = now.timeIntervalSince1970
        let dishwasher = ActivityJob(
            id: "dishwasher", kind: "dishwasher", title: "Dishwasher", status: "Eco 50° · 62%", phase: .running,
            startTs: t - 8_000, endTs: t + 2_520, progress: 0.62, symbol: "dishwasher", tint: "cleaning",
            controls: [ActivityControl(id: "stop", title: "Stop", role: .destructive)])
        func fan(_ room: String, minutes: Double) -> ActivityJob {
            ActivityJob(id: "fan.\(room)", kind: "bathroom_fan", title: "\(room.capitalized) Bath Fan", status: "Off in",
                        startTs: t - 300, endTs: t + minutes * 60, symbol: "fan", tint: "air",
                        controls: [ActivityControl(id: "cancel_timer", title: "Cancel Timer")])
        }
        let url = "/sfenton-react-dash/home?path=kitchen"
        switch scenario {
        case .dishwasher:
            return HomeActivityState(url: url, jobs: [dishwasher])
        case .fan:
            return HomeActivityState(url: "/sfenton-react-dash/home?path=master-bathroom", jobs: [fan("master", minutes: 12)])
        case .two:
            return HomeActivityState(url: url, jobs: [fan("master", minutes: 12), dishwasher])
        case .three:
            return HomeActivityState(focus: "fan.master", url: "/sfenton-react-dash/home?path=master-bathroom",
                                     jobs: [fan("guest", minutes: 5), fan("master", minutes: 12), dishwasher])
        case .six:
            var dryer = ActivityJob(id: "dryer", kind: "dryer", title: "Dryer", status: "Running", endTs: t + 1_200, estimated: true,
                                    symbol: "dryer", tint: "cleaning")
            dryer.controls = []
            let vacuum = ActivityJob(id: "vacuum", kind: "vacuum", title: "Upstairs Vacuum", status: "Kitchen · 2 of 5 rooms",
                                     progress: 0.4, symbol: "fan", tint: "cleaning")
            let washer = ActivityJob(id: "washer", kind: "washer", title: "Washer", status: "Spinning", symbol: "washer", tint: "cleaning")
            return HomeActivityState(focus: "dishwasher", url: url,
                                     jobs: [fan("guest", minutes: 5), fan("master", minutes: 12), dryer, dishwasher, vacuum, washer])
        case .done:
            var done = dishwasher
            done.phase = .done
            done.status = "Clean"
            done.endTs = nil
            done.progress = nil
            done.controls = []
            return HomeActivityState(url: url, jobs: [done])
        case .attention:
            var attention = dishwasher
            attention.phase = .attention
            attention.status = "Needs attention"
            attention.endTs = nil
            attention.progress = nil
            return HomeActivityState(url: url, jobs: [attention])
        case .stopping:
            return HomeActivityState(url: url, jobs: [dishwasher]).stopping("dishwasher")
        }
    }

    /// A state from a debug launch value: a scenario name, or the base64 of a content-state JSON.
    public static func state(fromLaunchValue value: String, now: Date = Date()) -> HomeActivityState? {
        if let scenario = Scenario(rawValue: value) { return state(scenario, now: now) }
        guard let data = Data(base64Encoded: value) else { return nil }
        return try? HomeActivityState.decode(data)
    }
}
