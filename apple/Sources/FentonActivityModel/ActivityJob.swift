import Foundation

/// Where a running household job is (`phase` on the wire, `.agents/platforms/apple/live-activities.md` §3).
public enum JobPhase: String, Codable, Hashable, Sendable, CaseIterable {
    /// Doing its work now.
    case running
    /// Paused by the person or the device.
    case paused
    /// Scheduled to start (a delayed start).
    case waiting
    /// Needs a person (action required, or an error).
    case attention
    /// A control was pressed and Home Assistant has not confirmed yet (optimistic).
    case stopping
    /// Finished; shown for the linger time.
    case done

    /// A phase this build does not know reads as ``running`` so a newer engine never breaks an older app.
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = JobPhase(rawValue: raw) ?? .running
    }

    /// Whether the job still counts as running in the header.
    public var isActive: Bool { self != .done }
}

/// One button on a job (`controls` on the wire). At most ``HomeActivityState/maxControlsPerJob`` ride along.
public struct ActivityControl: Codable, Hashable, Sendable, Identifiable {
    /// How the button reads.
    public enum Role: String, Codable, Hashable, Sendable {
        case normal
        case destructive

        /// An unknown role reads as ``normal``.
        public init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Role(rawValue: raw) ?? .normal
        }
    }

    /// The control's id, which Home Assistant maps to a service (`stop`, `cancel_timer`).
    public var id: String
    /// The label.
    public var title: String
    /// Normal or destructive.
    public var role: Role

    /// Creates a control.
    public init(id: String, title: String, role: Role = .normal) {
        self.id = id
        self.title = title
        self.role = role
    }

    private enum CodingKeys: String, CodingKey { case id, title, role }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        role = try container.decodeIfPresent(Role.self, forKey: .role) ?? .normal
    }
}

/// One job in the Home activity: a dishwasher cycle, a fan timer, a laundry run.
///
/// `startTs` and `endTs` are **Unix seconds as numbers**. ActivityKit decodes push content with a default
/// `JSONDecoder`, so a `Date` field would read the number as seconds since 2001 and land 31 years early; the
/// wire keeps doubles and ``startDate`` / ``endDate`` convert.
public struct ActivityJob: Codable, Hashable, Sendable, Identifiable {
    /// Stable id (`dishwasher`, `fan.master`).
    public var id: String
    /// The kind (`dishwasher`, `bathroom_fan`).
    public var kind: String
    /// The name shown (`Dishwasher`).
    public var title: String
    /// Short status text, at most ``HomeActivityState/maxStatusLength`` characters (`Eco 50° · Drying`).
    public var status: String
    /// Where the job is.
    public var phase: JobPhase
    /// When it started, Unix seconds.
    public var startTs: Double?
    /// When it ends (or is estimated to), Unix seconds.
    public var endTs: Double?
    /// The end is a guess (the dryer): show "About" and a clock time, never a seconds countdown.
    public var estimated: Bool
    /// 0...1 when the device reports progress.
    public var progress: Double?
    /// SF Symbol name.
    public var symbol: String
    /// Colour family (a `ColorFamily` raw value such as `cleaning` or `air`).
    public var tint: String
    /// Up to two buttons.
    public var controls: [ActivityControl]

    /// Creates a job.
    public init(id: String, kind: String, title: String, status: String, phase: JobPhase = .running,
                startTs: Double? = nil, endTs: Double? = nil, estimated: Bool = false, progress: Double? = nil,
                symbol: String = "circle", tint: String = "neutral", controls: [ActivityControl] = []) {
        self.id = id
        self.kind = kind
        self.title = title
        self.status = status
        self.phase = phase
        self.startTs = startTs
        self.endTs = endTs
        self.estimated = estimated
        self.progress = progress
        self.symbol = symbol
        self.tint = tint
        self.controls = controls
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, title, status, phase, estimated, progress, symbol, tint, controls
        case startTs = "start_ts"
        case endTs = "end_ts"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? "generic"
        title = try container.decode(String.self, forKey: .title)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
        phase = try container.decodeIfPresent(JobPhase.self, forKey: .phase) ?? .running
        startTs = try container.decodeIfPresent(Double.self, forKey: .startTs)
        endTs = try container.decodeIfPresent(Double.self, forKey: .endTs)
        estimated = try container.decodeIfPresent(Bool.self, forKey: .estimated) ?? false
        progress = try container.decodeIfPresent(Double.self, forKey: .progress)
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol) ?? "circle"
        tint = try container.decodeIfPresent(String.self, forKey: .tint) ?? "neutral"
        controls = try container.decodeIfPresent([ActivityControl].self, forKey: .controls) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(title, forKey: .title)
        try container.encode(status, forKey: .status)
        try container.encode(phase, forKey: .phase)
        try container.encodeIfPresent(startTs, forKey: .startTs)
        try container.encodeIfPresent(endTs, forKey: .endTs)
        if estimated { try container.encode(true, forKey: .estimated) }
        try container.encodeIfPresent(progress, forKey: .progress)
        try container.encode(symbol, forKey: .symbol)
        try container.encode(tint, forKey: .tint)
        if !controls.isEmpty { try container.encode(controls, forKey: .controls) }
    }

    // MARK: - Dates

    /// ``startTs`` as a date.
    public var startDate: Date? { startTs.map { Date(timeIntervalSince1970: $0) } }
    /// ``endTs`` as a date.
    public var endDate: Date? { endTs.map { Date(timeIntervalSince1970: $0) } }

    /// The range a `Text(timerInterval:)` or `ProgressView(timerInterval:)` counts through; nil without both ends,
    /// when the end is an estimate (``estimated``), or when it is not after the start.
    public var timerRange: ClosedRange<Date>? {
        guard !estimated, let start = startDate, let end = endDate, end > start else { return nil }
        return start...end
    }

    // MARK: - Presentation

    /// The trailing content of a job row.
    public enum Trailing: Hashable, Sendable {
        /// A live countdown to the end.
        case countdown(ClosedRange<Date>)
        /// "About 3:40 PM" (an estimated end).
        case approximately(Date)
        /// A delayed start, at the date.
        case startsAt(Date)
        /// A percentage, for a job that reports progress but no end time.
        case percent(Int)
        /// Paused.
        case paused
        /// Needs a person.
        case attention
        /// Finished.
        case done
        /// Nothing to show.
        case none
    }

    /// What the trailing side of a row shows.
    public var trailing: Trailing {
        switch phase {
        case .done: return .done
        case .attention: return .attention
        case .paused: return .paused
        case .waiting:
            return endDate.map(Trailing.startsAt) ?? .none
        default: break
        }
        if estimated, let end = endDate { return .approximately(end) }
        if let range = timerRange { return .countdown(range) }
        if let progress { return .percent(Int((min(max(progress, 0), 1) * 100).rounded())) }
        return .none
    }

    /// How the bar under a row fills.
    public enum Bar: Hashable, Sendable {
        /// Fills itself as time passes (`ProgressView(timerInterval:)`).
        case timer(ClosedRange<Date>)
        /// A reported fraction.
        case fraction(Double)
        /// Complete.
        case full
        /// No bar.
        case hidden
    }

    /// The bar under the row.
    public var bar: Bar {
        switch phase {
        case .done: return .full
        case .attention, .waiting, .paused: return .hidden
        default: break
        }
        if let range = timerRange { return .timer(range) }
        if let progress { return .fraction(min(max(progress, 0), 1)) }
        return .hidden
    }

    // MARK: - Speech

    /// The row read out as one phrase: "Dishwasher, Eco 50 degrees, Drying, 42 minutes left".
    /// - Parameter now: Where "left" counts from.
    public func spokenSummary(now: Date = Date()) -> String {
        var parts = [title]
        let cleaned = status.replacingOccurrences(of: "°", with: " degrees").replacingOccurrences(of: " · ", with: ", ")
        if !cleaned.isEmpty { parts.append(cleaned) }
        switch trailing {
        case let .countdown(range): parts.append(Self.spokenRemaining(until: range.upperBound, now: now))
        case let .approximately(date): parts.append("about " + Self.spokenClock(date))
        case let .startsAt(date): parts.append("starts at " + Self.spokenClock(date))
        case let .percent(value): parts.append("\(value) percent")
        case .paused: parts.append("paused")
        case .attention: parts.append("needs attention")
        case .done: parts.append("done")
        case .none: break
        }
        return parts.joined(separator: ", ")
    }

    /// "42 minutes left", "1 hour 5 minutes left", "less than a minute left", or "done" once past.
    public static func spokenRemaining(until end: Date, now: Date) -> String {
        let seconds = Int(end.timeIntervalSince(now).rounded(.up))
        guard seconds > 0 else { return "done" }
        if seconds < 60 { return "less than a minute left" }
        let minutes = (seconds + 59) / 60
        let hours = minutes / 60, rest = minutes % 60
        func unit(_ value: Int, _ word: String) -> String { "\(value) \(word)\(value == 1 ? "" : "s")" }
        if hours == 0 { return unit(minutes, "minute") + " left" }
        return (rest == 0 ? unit(hours, "hour") : unit(hours, "hour") + " " + unit(rest, "minute")) + " left"
    }

    private static func spokenClock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
