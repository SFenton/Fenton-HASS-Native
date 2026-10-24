import Foundation

/// Seconds a ticker has played, kept across pauses.
struct TickerClock: Equatable {
    private var before: TimeInterval = 0
    private var resumedAt: Date?

    var isRunning: Bool { resumedAt != nil }

    func elapsed(at date: Date) -> TimeInterval {
        before + (resumedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }

    mutating func resume(at date: Date) { if resumedAt == nil { resumedAt = date } }

    mutating func pause(at date: Date) {
        before = elapsed(at: date)
        resumedAt = nil
    }

    /// Back to the start (the text changed).
    mutating func restart() {
        before = 0
        resumedAt = nil
    }
}
