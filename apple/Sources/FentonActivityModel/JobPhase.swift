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
