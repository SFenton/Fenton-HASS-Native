import FentonActivityModel
import Foundation
@testable import HassCore
import Testing

/// Entities as the Home Assistant instance reports them (verified 2026-10-17, `live-activities.md` §8).
enum LiveActivityFixtures {
    static let now = Date(timeIntervalSince1970: 1_792_249_200)

    static func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    static func reader(_ states: [EntityState]) -> (String) -> EntityState? {
        let map = Dictionary(uniqueKeysWithValues: states.map { ($0.entityId, $0) })
        return { map[$0] }
    }

    /// A running Eco 50° cycle, 40 minutes from the end, 62% done.
    static func dishwasher(operation: String = "run", remote: Bool = true, program: String? = "dishcare_dishwasher_program_eco_50",
                           finishesIn: TimeInterval = 2_400, progress: String = "62") -> [EntityState] {
        var states = [
            EntityState(entityId: "sensor.dishwasher_operation_state", state: operation, lastChanged: now.addingTimeInterval(-7_200)),
            EntityState(entityId: "sensor.dishwasher_program_finish_time", state: iso(now.addingTimeInterval(finishesIn))),
            EntityState(entityId: "sensor.dishwasher_program_progress", state: progress),
            EntityState(entityId: "binary_sensor.dishwasher_remote_control", state: remote ? "on" : "off"),
        ]
        if let program { states.append(EntityState(entityId: "select.dishwasher_active_program", state: program)) }
        return states
    }

    /// A bathroom fan timer ending in `minutes`, set 5 minutes ago.
    static func fan(_ room: String = "master", minutes: Double = 25) -> [EntityState] {
        [
            EntityState(entityId: "input_boolean.\(room)_bathroom_fan_timer_pending", state: "on", lastChanged: now.addingTimeInterval(-300)),
            EntityState(entityId: "input_datetime.\(room)_bathroom_fan_timer_ends_at", state: "2026-10-17 15:25:00",
                        attributes: ["timestamp": .number(now.addingTimeInterval(minutes * 60).timeIntervalSince1970)]),
        ]
    }
}

struct HomeJobDeriverTests {
    private let now = LiveActivityFixtures.now
    private let deriver = HomeJobDeriver()

    private func jobs(_ states: [EntityState]) -> [ActivityJob] {
        deriver.jobs(entity: LiveActivityFixtures.reader(states), now: now)
    }

    @Test func aRunningDishwasherIsOneJobWithACountdownAndAStopButton() throws {
        let job = try #require(jobs(LiveActivityFixtures.dishwasher()).first)
        #expect(job.id == "dishwasher" && job.title == "Dishwasher" && job.phase == .running)
        #expect(job.status == "Eco 50° · 62%")
        #expect(job.endTs == now.addingTimeInterval(2_400).timeIntervalSince1970)
        #expect(job.startTs == now.addingTimeInterval(-7_200).timeIntervalSince1970)
        #expect(job.progress == 0.62 && job.symbol == "dishwasher" && job.tint == "cleaning")
        #expect(job.controls == [ActivityControl(id: "stop", title: "Stop", role: .destructive)])
    }

    @Test func pausedOffersResumeAndStop() throws {
        let job = try #require(jobs(LiveActivityFixtures.dishwasher(operation: "pause")).first)
        #expect(job.phase == .paused && job.status == "Eco 50° · Paused")
        #expect(job.controls.map(\.id) == ["resume", "stop"])
    }

    @Test func noButtonsWithoutRemoteControl() throws {
        let job = try #require(jobs(LiveActivityFixtures.dishwasher(remote: false)).first)
        #expect(job.controls.isEmpty)
    }

    @Test func delayedStartWaitsWithoutATimer() throws {
        let job = try #require(jobs(LiveActivityFixtures.dishwasher(operation: "delayedstart")).first)
        #expect(job.phase == .waiting && job.status == "Delayed start")
        #expect(job.endTs == nil && job.startTs == nil && job.progress == nil)
        #expect(job.controls.map(\.id) == ["stop"])
    }

    @Test func attentionStoppingAndFinishedPhases() throws {
        let action = try #require(jobs(LiveActivityFixtures.dishwasher(operation: "actionrequired")).first)
        #expect(action.phase == .attention && action.status == "Needs attention" && action.controls.isEmpty)
        let error = try #require(jobs(LiveActivityFixtures.dishwasher(operation: "error")).first)
        #expect(error.status == "Error")
        let aborting = try #require(jobs(LiveActivityFixtures.dishwasher(operation: "aborting")).first)
        #expect(aborting.phase == .stopping && aborting.status == "Stopping…")
        let finished = try #require(jobs(LiveActivityFixtures.dishwasher(operation: "finished")).first)
        #expect(finished.phase == .done && finished.status == "Clean" && finished.endTs == nil && finished.controls.isEmpty)
    }

    @Test func idleAndUnavailableDishwashersAreNotJobs() {
        for state in ["inactive", "ready", "unknown", "unavailable", "something_new"] {
            #expect(jobs(LiveActivityFixtures.dishwasher(operation: state)).isEmpty, "\(state)")
        }
        #expect(jobs([]).isEmpty)
    }

    @Test func missingDetailsDegradeGracefully() throws {
        let noProgram = try #require(jobs(LiveActivityFixtures.dishwasher(program: nil, progress: "unknown")).first)
        #expect(noProgram.status == "Running" && noProgram.progress == nil)
        let clamped = try #require(jobs(LiveActivityFixtures.dishwasher(progress: "140")).first)
        #expect(clamped.progress == 1)
        var states = LiveActivityFixtures.dishwasher()
        states.removeAll { $0.entityId == "sensor.dishwasher_program_finish_time" }
        #expect(try #require(jobs(states).first).endTs == nil)
        states.append(EntityState(entityId: "sensor.dishwasher_program_finish_time", state: "unavailable"))
        #expect(try #require(jobs(states).first).endTs == nil)
        var unknownChange = LiveActivityFixtures.dishwasher()
        unknownChange[0] = EntityState(entityId: "sensor.dishwasher_operation_state", state: "run")
        #expect(try #require(jobs(unknownChange).first).startTs == nil)
    }

    @Test func programSlugsReadAsLabels() {
        #expect(HomeJobDeriver.programLabel("dishcare_dishwasher_program_eco_50") == "Eco 50°")
        #expect(HomeJobDeriver.programLabel("dishcare_dishwasher_program_auto_2") == "Auto 2")
        #expect(HomeJobDeriver.programLabel("dishcare_dishwasher_program_intensive_70") == "Intensive 70°")
        #expect(HomeJobDeriver.programLabel("quick") == "Quick")
        #expect(HomeJobDeriver.programLabel("") == nil)
        #expect(HomeJobDeriver.programLabel("program_") == nil)
    }

    @Test func aPendingFanTimerIsAJobUntilItsDeadline() throws {
        let job = try #require(jobs(LiveActivityFixtures.fan()).first)
        #expect(job.id == "fan.master" && job.title == "Master Bath Fan" && job.status == "Off in")
        #expect(job.endTs == now.addingTimeInterval(1_500).timeIntervalSince1970)
        #expect(job.startTs == now.addingTimeInterval(-300).timeIntervalSince1970)
        #expect(job.symbol == "fan" && job.tint == "air")
        #expect(job.controls == [ActivityControl(id: "cancel_timer", title: "Cancel Timer")])
        #expect(jobs(LiveActivityFixtures.fan(minutes: -1)).isEmpty, "a deadline in the past is not a job")
    }

    @Test func fansNeedAPendingFlagAndADeadline() {
        var off = LiveActivityFixtures.fan()
        off[0] = EntityState(entityId: "input_boolean.master_bathroom_fan_timer_pending", state: "off")
        #expect(jobs(off).isEmpty)
        #expect(jobs([off[0]]).isEmpty)
        var noDeadline = LiveActivityFixtures.fan()
        noDeadline[1] = EntityState(entityId: "input_datetime.master_bathroom_fan_timer_ends_at", state: "unavailable")
        #expect(jobs(noDeadline).isEmpty)
    }

    @Test func aFanFallsBackToTheLocalDateTimeAndToNowForItsStart() throws {
        let local = DateFormatter()
        local.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let later = local.string(from: now.addingTimeInterval(600))
        let states = [
            EntityState(entityId: "input_boolean.guest_bathroom_fan_timer_pending", state: "on"),
            EntityState(entityId: "input_datetime.guest_bathroom_fan_timer_ends_at", state: later),
        ]
        let job = try #require(jobs(states).first)
        #expect(job.title == "Guest Bath Fan")
        #expect(job.startTs == now.timeIntervalSince1970, "an unknown change time starts the bar at the first look")
        #expect(abs((job.endTs ?? 0) - now.addingTimeInterval(600).timeIntervalSince1970) < 1)
    }

    @Test func jobsComeMostUrgentFirstAndTheirPagesMap() {
        let all = jobs(LiveActivityFixtures.dishwasher(finishesIn: 3_000) + LiveActivityFixtures.fan("master", minutes: 10)
                       + LiveActivityFixtures.fan("guest", minutes: 5))
        #expect(all.map(\.id) == ["fan.guest", "fan.master", "dishwasher"])
        #expect(HomeJobDeriver.url(for: all[2]) == "/sfenton-react-dash/home?path=kitchen")
        #expect(HomeJobDeriver.url(for: all[1]) == "/sfenton-react-dash/home?path=master-bathroom")
        #expect(HomeJobDeriver.url(for: ActivityJob(id: "dryer", kind: "d", title: "D", status: "")) == "/sfenton-react-dash/home?path=overview")
    }

    @Test func watchedEntitiesCoverEverythingRead() {
        let watched = Set(deriver.watchedEntityIDs)
        #expect(watched.contains("sensor.dishwasher_operation_state") && watched.contains("input_boolean.guest_bathroom_fan_timer_pending"))
        #expect(watched.count == 9)
        #expect(HomeJobDeriver(fans: []).watchedEntityIDs.count == 5)
    }
}
