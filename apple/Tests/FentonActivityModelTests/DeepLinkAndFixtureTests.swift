import Foundation
@testable import FentonActivityModel
import Testing

struct ActivityDeepLinkTests {
    @Test func aStateLinksToItsDashboardPathAndBack() throws {
        let state = HomeActivityState(url: "/sfenton-react-dash/home?path=kitchen", jobs: [])
        let url = try #require(ActivityDeepLink.url(for: state))
        #expect(url.scheme == "fentonhome" && url.host == "liveactivity")
        #expect(ActivityDeepLink.link(from: url) == "/sfenton-react-dash/home?path=kitchen")
    }

    @Test func noPathMeansNoLink() {
        #expect(ActivityDeepLink.url(for: HomeActivityState(jobs: [])) == nil)
        #expect(ActivityDeepLink.url(for: HomeActivityState(url: "", jobs: [])) == nil)
    }

    @Test func onlyLiveActivityLinksAreRead() {
        #expect(ActivityDeepLink.link(from: URL(string: "https://example.com/?url=x")!) == nil)
        #expect(ActivityDeepLink.link(from: URL(string: "fentonhome://other?url=x")!) == nil)
        #expect(ActivityDeepLink.link(from: URL(string: "fentonhome://liveactivity")!) == nil)
        #expect(ActivityDeepLink.link(from: URL(string: "fentonhome://liveactivity?url=")!) == nil)
    }
}

struct HomeActivityFixturesTests {
    private let now = ActivityFixtures.now

    @Test func everyScenarioFitsTheWireBudgetAndPointsIntoTheFuture() throws {
        for scenario in HomeActivityFixtures.Scenario.allCases {
            let state = HomeActivityFixtures.state(scenario, now: now)
            #expect(state == state.fitted(), "\(scenario) is within the budget")
            #expect(try state.encoded().count < HomeActivityState.maxPayloadBytes / 2)
            #expect(state.focusedJob != nil)
            for job in state.jobs where job.phase.isActive {
                if let end = job.endDate { #expect(end > now, "\(scenario) \(job.id)") }
            }
        }
    }

    @Test func scenariosHaveTheShapeTheirNameSays() {
        #expect(HomeActivityFixtures.state(.dishwasher, now: now).jobs.count == 1)
        #expect(HomeActivityFixtures.state(.fan, now: now).jobs[0].id == "fan.master")
        #expect(HomeActivityFixtures.state(.two, now: now).jobs.count == 2)
        let three = HomeActivityFixtures.state(.three, now: now)
        #expect(three.jobs.count == 3 && three.focus == "fan.master")
        #expect(HomeActivityFixtures.state(.six, now: now).jobs.count == HomeActivityState.maxJobs)
        #expect(HomeActivityFixtures.state(.done, now: now).isAllDone)
        #expect(HomeActivityFixtures.state(.attention, now: now).jobs[0].phase == .attention)
        let stopping = HomeActivityFixtures.state(.stopping, now: now).jobs[0]
        #expect(stopping.phase == .stopping && stopping.controls.isEmpty)
    }

    @Test func launchValuesAreScenarioNamesOrBase64Content() throws {
        #expect(HomeActivityFixtures.state(fromLaunchValue: "three", now: now) == HomeActivityFixtures.state(.three, now: now))
        let custom = HomeActivityFixtures.state(.fan, now: now)
        let encoded = try custom.encoded().base64EncodedString()
        #expect(HomeActivityFixtures.state(fromLaunchValue: encoded, now: now) == custom)
        #expect(HomeActivityFixtures.state(fromLaunchValue: "!!not base64!!", now: now) == nil)
        #expect(HomeActivityFixtures.state(fromLaunchValue: Data("nope".utf8).base64EncodedString(), now: now) == nil)
    }
}
