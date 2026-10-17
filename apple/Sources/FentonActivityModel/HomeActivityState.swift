import Foundation

/// The Home activity's content: every running household job, which one the Dynamic Island shows, and where a tap goes
/// (`aps.content-state`, `.agents/platforms/apple/live-activities.md` §3). Home Assistant composes it; the app writes
/// it locally only for an optimistic button state and for a foreground start.
public struct HomeActivityState: Codable, Hashable, Sendable {
    /// The content-state schema this build writes.
    public static let currentVersion = 1
    /// Jobs listed at most.
    public static let maxJobs = 6
    /// Buttons on a job at most (HIG: one or two essential controls).
    public static let maxControlsPerJob = 2
    /// Status text at most.
    public static let maxStatusLength = 40
    /// Job rows the Lock Screen draws; the rest read "+N more".
    public static let maxLockScreenRows = 3
    /// Apple's limit for the whole push, static and dynamic attributes together.
    public static let maxPayloadBytes = 4096

    /// The schema version (`v`).
    public var version: Int
    /// The job the Dynamic Island shows and whose controls the Lock Screen offers; nil means the first.
    public var focus: String?
    /// Where a tap goes: a dashboard path read like a notification's `url` (`PushLink`).
    public var url: String?
    /// The jobs, most urgent first (Home Assistant owns the order).
    public var jobs: [ActivityJob]

    /// Creates a state.
    public init(version: Int = HomeActivityState.currentVersion, focus: String? = nil, url: String? = nil,
                jobs: [ActivityJob]) {
        self.version = version
        self.focus = focus
        self.url = url
        self.jobs = jobs
    }

    private enum CodingKeys: String, CodingKey {
        case version = "v"
        case focus, url, jobs
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        focus = try container.decodeIfPresent(String.self, forKey: .focus)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        jobs = try container.decodeIfPresent([ActivityJob].self, forKey: .jobs) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encodeIfPresent(focus, forKey: .focus)
        try container.encodeIfPresent(url, forKey: .url)
        try container.encode(jobs, forKey: .jobs)
    }

    // MARK: - Reading

    /// The job the Dynamic Island shows: ``focus`` when still listed, else the first.
    public var focusedJob: ActivityJob? {
        jobs.first { $0.id == focus } ?? jobs.first
    }

    /// Jobs not yet done: the header's count.
    public var runningCount: Int { jobs.filter { $0.phase.isActive }.count }

    /// Every job is finished (the linger).
    public var isAllDone: Bool { !jobs.isEmpty && jobs.allSatisfy { $0.phase == .done } }

    /// The Lock Screen's rows: the first `limit` jobs, with the focused job swapped in for the last row when it would
    /// fall below the fold, so the job the controls belong to is always on screen.
    /// - Parameter limit: Rows that fit (``maxLockScreenRows`` unless the controls line or a large text size takes room).
    public func lockScreenRows(limit: Int = HomeActivityState.maxLockScreenRows) -> [ActivityJob] {
        let limit = max(1, limit)
        guard jobs.count > limit else { return jobs }
        var rows = Array(jobs.prefix(limit))
        if let focused = focusedJob, !rows.contains(where: { $0.id == focused.id }) {
            rows[rows.count - 1] = focused
        }
        return rows
    }

    /// Jobs not drawn on the Lock Screen ("+2 more").
    public func overflowCount(limit: Int = HomeActivityState.maxLockScreenRows) -> Int { max(0, jobs.count - max(1, limit)) }

    /// The ‹ n of N › pager; nil with fewer than two jobs.
    public var pager: Pager? {
        guard jobs.count > 1, let focused = focusedJob, let index = jobs.firstIndex(where: { $0.id == focused.id }) else { return nil }
        let count = jobs.count
        return Pager(position: index + 1, count: count,
                     previous: jobs[(index - 1 + count) % count].id, next: jobs[(index + 1) % count].id)
    }

    /// Where the pager stands.
    public struct Pager: Hashable, Sendable {
        /// The focused job's place, from 1.
        public var position: Int
        /// How many jobs.
        public var count: Int
        /// The job before (wrapping).
        public var previous: String
        /// The job after (wrapping).
        public var next: String

        /// "2 of 3".
        public var label: String { "\(position) of \(count)" }
    }

    // MARK: - Changing

    /// The state with `id` focused; unchanged when no such job is listed.
    public func focusing(_ id: String) -> HomeActivityState {
        guard jobs.contains(where: { $0.id == id }) else { return self }
        var copy = self
        copy.focus = id
        return copy
    }

    /// The state with a job in the optimistic ``JobPhase/stopping`` phase and its controls hidden, right after a button.
    public func stopping(_ id: String) -> HomeActivityState {
        replacingJob(id) { job in
            job.phase = .stopping
            job.controls = []
        }
    }

    /// The state with `original` back in the list, restoring its controls and phase after a failed button.
    public func restoring(_ original: ActivityJob) -> HomeActivityState {
        replacingJob(original.id) { $0 = original }
    }

    private func replacingJob(_ id: String, _ change: (inout ActivityJob) -> Void) -> HomeActivityState {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return self }
        var copy = self
        change(&copy.jobs[index])
        return copy
    }

    // MARK: - Ordering

    /// Most urgent first: attention, then the soonest end, then jobs without an end, then finished jobs; ties by title.
    public static func urgencyOrdered(_ jobs: [ActivityJob]) -> [ActivityJob] {
        func rank(_ job: ActivityJob) -> Int {
            switch job.phase {
            case .attention: 0
            case .done: 3
            default: job.endTs == nil ? 2 : 1
            }
        }
        return jobs.sorted { lhs, rhs in
            let (left, right) = (rank(lhs), rank(rhs))
            if left != right { return left < right }
            if let a = lhs.endTs, let b = rhs.endTs, a != b { return a < b }
            if lhs.title != rhs.title { return lhs.title < rhs.title }
            return lhs.id < rhs.id
        }
    }

    // MARK: - Budget

    /// The state trimmed to the wire budget (``maxJobs``, ``maxControlsPerJob``, ``maxStatusLength``), keeping the
    /// focused job in the list.
    public func fitted() -> HomeActivityState {
        var copy = self
        var jobs = self.jobs
        if jobs.count > Self.maxJobs {
            var kept = Array(jobs.prefix(Self.maxJobs))
            if let focused = focusedJob, !kept.contains(where: { $0.id == focused.id }) { kept[kept.count - 1] = focused }
            jobs = kept
        }
        copy.jobs = jobs.map { job in
            var job = job
            if job.status.count > Self.maxStatusLength { job.status = String(job.status.prefix(Self.maxStatusLength - 1)) + "…" }
            job.controls = Array(job.controls.prefix(Self.maxControlsPerJob))
            return job
        }
        return copy
    }

    /// The JSON bytes of this state, as ActivityKit sends it.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    /// Decodes a state the way ActivityKit does (a default `JSONDecoder`, no custom strategies).
    public static func decode(_ data: Data) throws -> HomeActivityState {
        try JSONDecoder().decode(HomeActivityState.self, from: data)
    }
}
