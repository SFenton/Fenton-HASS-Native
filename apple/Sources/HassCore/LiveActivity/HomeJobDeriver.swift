import FentonActivityModel
import Foundation

/// Turns entity states into the Home activity's jobs while the app is open (Phase 1 foreground path,
/// `.agents/platforms/apple/live-activities.md` §6).
///
/// Home Assistant owns this derivation once the `fenton_push` job engine ships (Phase 2); until then the foreground
/// app reads the same entities the engine will, so the Lock Screen is right while the app is open. Entities verified
/// 2026-10-17: the dishwasher is a Bosch on Home Connect, the fans are the guest and master bathroom timers.
public struct HomeJobDeriver: Sendable {
    /// The dishwasher's entities.
    public enum Dishwasher {
        public static let id = "dishwasher"
        public static let operationState = "sensor.dishwasher_operation_state"
        public static let finishTime = "sensor.dishwasher_program_finish_time"
        public static let progress = "sensor.dishwasher_program_progress"
        public static let activeProgram = "select.dishwasher_active_program"
        public static let remoteControl = "binary_sensor.dishwasher_remote_control"
        /// The dashboard page a tap opens.
        public static let page = "kitchen"
    }

    private let fans: [BathroomFanConfig]

    /// Creates a deriver.
    /// - Parameter fans: The bathroom fans to watch.
    public init(fans: [BathroomFanConfig] = BathroomFanConfig.all) {
        self.fans = fans
    }

    /// Every entity the deriver reads, so a coordinator can watch exactly these.
    public var watchedEntityIDs: [String] {
        [Dishwasher.operationState, Dishwasher.finishTime, Dishwasher.progress, Dishwasher.activeProgram, Dishwasher.remoteControl]
            + fans.flatMap { [$0.pendingEntityId, $0.deadlineEntityId] }
    }

    /// The jobs running now, most urgent first.
    /// - Parameters:
    ///   - entity: Reads an entity's current state.
    ///   - now: The current time.
    public func jobs(entity: (String) -> EntityState?, now: Date) -> [ActivityJob] {
        var jobs: [ActivityJob] = []
        if let dishwasher = dishwasher(entity: entity) { jobs.append(dishwasher) }
        jobs += fans.compactMap { fan(for: $0, entity: entity, now: now) }
        return HomeActivityState.urgencyOrdered(jobs)
    }

    /// The page a tap on `job` opens, as a dashboard `url` (read like a notification's).
    public static func url(for job: ActivityJob) -> String {
        let page = job.id == Dishwasher.id ? Dishwasher.page : job.id.hasPrefix("fan.") ? "\(job.id.dropFirst(4))-bathroom" : "overview"
        return "/sfenton-react-dash/home?path=\(page)"
    }

    // MARK: - Dishwasher

    private func dishwasher(entity: (String) -> EntityState?) -> ActivityJob? {
        guard let operation = entity(Dishwasher.operationState), !operation.isUnavailable else { return nil }
        let phase: JobPhase
        switch operation.state {
        case "run": phase = .running
        case "pause": phase = .paused
        case "delayedstart": phase = .waiting
        case "actionrequired", "error": phase = .attention
        case "aborting": phase = .stopping
        case "finished": phase = .done
        default: return nil
        }
        let program = entity(Dishwasher.activeProgram).flatMap { $0.isUnavailable ? nil : Self.programLabel($0.state) }
        let percent = entity(Dishwasher.progress).flatMap(\.numericState).map { Int(min(max($0, 0), 100).rounded()) }
        let finish = entity(Dishwasher.finishTime).flatMap { $0.isUnavailable ? nil : HassDates.iso8601($0.state) }

        var status: String
        switch phase {
        case .running: status = [program, percent.map { "\($0)%" }].compactMap { $0 }.joined(separator: " · ")
        case .paused: status = [program, "Paused"].compactMap { $0 }.joined(separator: " · ")
        case .waiting: status = "Delayed start"
        case .attention: status = operation.state == "error" ? "Error" : "Needs attention"
        case .stopping: status = "Stopping…"
        case .done: status = "Clean"
        }
        if status.isEmpty { status = "Running" }

        var controls: [ActivityControl] = []
        let remote = entity(Dishwasher.remoteControl)?.state == "on"
        if remote {
            if phase == .paused { controls.append(ActivityControl(id: "resume", title: "Resume")) }
            if phase == .running || phase == .paused || phase == .waiting {
                controls.append(ActivityControl(id: "stop", title: "Stop", role: .destructive))
            }
        }

        let running = phase == .running || phase == .paused
        return ActivityJob(
            id: Dishwasher.id, kind: "dishwasher", title: "Dishwasher", status: status, phase: phase,
            startTs: running ? operation.lastChanged.timeIntervalSince1970.nonZero : nil,
            endTs: running ? finish?.timeIntervalSince1970 : nil,
            progress: running ? percent.map { Double($0) / 100 } : nil,
            symbol: "dishwasher", tint: "cleaning", controls: controls)
    }

    /// A readable program from Home Connect's slug: `dishcare_dishwasher_program_eco_50` reads "Eco 50°". Numbers of
    /// 30 and above are temperatures; smaller ones ("Auto 2") are part of the name.
    public static func programLabel(_ slug: String) -> String? {
        let tail = slug.components(separatedBy: "program_").last ?? slug
        let words = tail.split(separator: "_").map(String.init).filter { !$0.isEmpty }
        guard !words.isEmpty else { return nil }
        return words.map { word in
            if let number = Int(word) { return number >= 30 ? "\(number)°" : word }
            return word.prefix(1).uppercased() + word.dropFirst()
        }.joined(separator: " ").replacingOccurrences(of: " °", with: "°")
    }

    // MARK: - Bathroom fans

    private func fan(for config: BathroomFanConfig, entity: (String) -> EntityState?, now: Date) -> ActivityJob? {
        guard let pending = entity(config.pendingEntityId), pending.state == "on",
              let deadline = entity(config.deadlineEntityId).flatMap(Self.deadline), deadline > now else { return nil }
        let started = pending.lastChanged > .distantPast && pending.lastChanged < deadline ? pending.lastChanged : now
        return ActivityJob(
            id: "fan.\(config.id)", kind: "bathroom_fan", title: config.roomTitle.replacingOccurrences(of: "Bathroom", with: "Bath") + " Fan",
            status: "Off in", phase: .running, startTs: started.timeIntervalSince1970, endTs: deadline.timeIntervalSince1970,
            symbol: "fan", tint: "air", controls: [ActivityControl(id: "cancel_timer", title: "Cancel Timer")])
    }

    /// The helper's end time: the `timestamp` attribute, else the local date-time state (same rule as
    /// ``BathroomFanController/deadline``).
    static func deadline(_ entity: EntityState) -> Date? {
        guard !entity.isUnavailable else { return nil }
        if let timestamp = entity.attributes["timestamp"]?.number { return Date(timeIntervalSince1970: timestamp) }
        return HassDates.localDateTime(entity.state)
    }
}

private extension TimeInterval {
    /// nil for the epoch placeholder `Date.distantPast` produces (a state with no known change time).
    var nonZero: TimeInterval? { self > 0 ? self : nil }
}
