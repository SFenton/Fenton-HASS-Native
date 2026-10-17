#if DEBUG
import FentonActivityModel
import Foundation
import HassCore

/// Debug launch hooks for the Home Live Activity journeys (`.agents/platforms/apple/live-activities.md` §11).
///
/// - `FENTON_LIVE_ACTIVITY_FIXTURE=<scenario | base64 content-state>` starts a real activity locally with fixture
///   content, so a journey can lock the simulator and read the Lock Screen without Home Assistant or Apple's servers.
///   Scenario names are `HomeActivityFixtures.Scenario`.
/// - `FENTON_LIVE_ACTIVITY_UPDATE=<scenario | base64>` updates the activity just started (after two seconds), and
///   `FENTON_LIVE_ACTIVITY_END=1` ends it after four: the same start, update and end a push would do.
enum LiveActivityDebugLaunch {
    static func startIfRequested(client: SystemLiveActivityClient,
                                 environment: [String: String] = ProcessInfo.processInfo.environment) {
        guard let value = environment["FENTON_LIVE_ACTIVITY_FIXTURE"], !value.isEmpty,
              let state = HomeActivityFixtures.state(fromLaunchValue: value) else { return }
        let update = environment["FENTON_LIVE_ACTIVITY_UPDATE"].flatMap { HomeActivityFixtures.state(fromLaunchValue: $0) }
        let end = environment["FENTON_LIVE_ACTIVITY_END"] == "1"
        Task {
            // Replace any activity a previous launch left, so each run starts clean.
            for record in await client.current() { await client.end(id: record.id, state: nil, dismissal: .immediate) }
            guard let record = try? await client.request(attributes: HomeActivityAttributes(), state: state, staleDate: nil) else {
                NSLog("FENTON_LIVE_ACTIVITY: the system refused the activity")
                return
            }
            NSLog("FENTON_LIVE_ACTIVITY: started %@", record.id)
            if let update {
                try? await Task.sleep(for: .seconds(2))
                await client.update(id: record.id, state: update, staleDate: nil)
                NSLog("FENTON_LIVE_ACTIVITY: updated %@", record.id)
            }
            if end {
                try? await Task.sleep(for: .seconds(2))
                await client.end(id: record.id, state: nil, dismissal: .immediate)
                NSLog("FENTON_LIVE_ACTIVITY: ended %@", record.id)
            }
        }
    }
}
#endif
