import Foundation
import os

/// One telemetry sample.
public struct TelemetryRecord: Codable, Equatable, Sendable {
    /// When it was recorded.
    public var date: Date
    /// What it measures: a ``Telemetry/Name`` value or a counter name.
    public var kind: String
    /// The page it belongs to, when known.
    public var page: String?
    /// Duration in milliseconds, for intervals.
    public var durationMs: Double?
    /// A number that goes with it (entities changed, hitch milliseconds, bytes).
    public var value: Double?
    /// A short note (`hit`, `304`, an entity id).
    public var detail: String?

    /// Creates a record.
    public init(date: Date = .now, kind: String, page: String? = nil, durationMs: Double? = nil, value: Double? = nil, detail: String? = nil) {
        self.date = date
        self.kind = kind
        self.page = page
        self.durationMs = durationMs
        self.value = value
        self.detail = detail
    }
}

/// Summary statistics for one kind of record.
public struct TelemetryStats: Codable, Equatable, Sendable {
    /// How many samples.
    public var count: Int
    /// Mean duration (or value, for point events) in milliseconds.
    public var mean: Double
    /// 50th percentile.
    public var p50: Double
    /// 95th percentile.
    public var p95: Double
    /// Largest sample.
    public var max: Double

    /// Summarizes `samples`; `nil` when empty.
    public init?(_ samples: [Double]) {
        guard !samples.isEmpty else { return nil }
        let sorted = samples.sorted()
        count = sorted.count
        mean = sorted.reduce(0, +) / Double(sorted.count)
        p50 = Self.percentile(sorted, 0.5)
        p95 = Self.percentile(sorted, 0.95)
        max = sorted[sorted.count - 1]
    }

    /// Nearest-rank percentile of an ascending array.
    static func percentile(_ sorted: [Double], _ fraction: Double) -> Double {
        let rank = Int((fraction * Double(sorted.count)).rounded(.up))
        return sorted[Swift.max(0, Swift.min(sorted.count - 1, rank - 1))]
    }
}

/// Scroll smoothness for one page: frames drawn while scrolling and how many missed their deadline.
public struct ScrollStats: Codable, Equatable, Sendable {
    /// Seconds spent scrolling.
    public var scrollSeconds: Double = 0
    /// Frames drawn while scrolling.
    public var frames: Int = 0
    /// Frames that missed their deadline.
    public var hitches: Int = 0
    /// Total time past deadlines, in milliseconds.
    public var hitchMs: Double = 0
    /// The longest frame, in milliseconds.
    public var worstFrameMs: Double = 0

    /// Milliseconds of hitch per second of scrolling, Apple's hitch-time ratio (under 5 is good, over 10 is
    /// noticeable).
    public var hitchRatio: Double { scrollSeconds > 0 ? hitchMs / scrollSeconds : 0 }

    /// Creates empty stats.
    public init() {}
}

/// The exported telemetry file.
public struct TelemetryExport: Codable, Sendable {
    /// When it was exported.
    public var exportedAt: Date
    /// Build and device facts.
    public var environment: [String: String]
    /// Counter totals.
    public var counters: [String: Int]
    /// Stats per record kind, and per kind and page as `kind@page`.
    public var stats: [String: TelemetryStats]
    /// Scroll smoothness per page.
    public var scroll: [String: ScrollStats]
    /// The most recent samples, oldest first.
    public var records: [TelemetryRecord]
}

/// The in-app telemetry store: a bounded ring of samples, counters and per-page scroll stats.
///
/// Thread-safe; the image cache records from background decoding.
public final class TelemetryLog: Sendable {
    struct Storage {
        var records: [TelemetryRecord] = []
        var head = 0
        var counters: [String: Int] = [:]
        var scroll: [String: ScrollStats] = [:]
    }

    /// The most samples kept; older ones are overwritten.
    public let capacity: Int
    private let storage = OSAllocatedUnfairLock(initialState: Storage())

    /// Creates a log.
    public init(capacity: Int = 4000) {
        self.capacity = capacity
    }

    // MARK: Writing

    /// Adds a sample, overwriting the oldest when full.
    public func record(_ record: TelemetryRecord) {
        let capacity = capacity
        storage.withLock { storage in
            if storage.records.count < capacity {
                storage.records.append(record)
            } else {
                storage.records[storage.head] = record
                storage.head = (storage.head + 1) % capacity
            }
        }
    }

    /// Adds to a counter.
    public func increment(_ counter: String, by amount: Int = 1) {
        storage.withLock { $0.counters[counter, default: 0] += amount }
    }

    /// Adds frames from a scroll on `page`.
    /// - Parameters:
    ///   - page: The page that scrolled.
    ///   - frameMs: Each frame's duration in milliseconds.
    ///   - budgetMs: The display's frame budget (16.7 at 60 Hz, 8.3 at 120 Hz).
    public func addScroll(page: String, frameMs: [Double], budgetMs: Double) {
        guard !frameMs.isEmpty else { return }
        storage.withLock { storage in
            var stats = storage.scroll[page] ?? ScrollStats()
            for frame in frameMs {
                stats.frames += 1
                stats.scrollSeconds += frame / 1000
                stats.worstFrameMs = max(stats.worstFrameMs, frame)
                // A frame counts as a hitch once it runs past half a budget late, so jitter isn't counted.
                let late = frame - budgetMs
                if late > budgetMs / 2 {
                    stats.hitches += 1
                    stats.hitchMs += late
                }
            }
            storage.scroll[page] = stats
        }
    }

    /// Forgets everything.
    public func reset() {
        storage.withLock { $0 = Storage() }
    }

    // MARK: Reading

    /// Samples, oldest first.
    public var records: [TelemetryRecord] {
        storage.withLock { storage in
            Array(storage.records[storage.head...] + storage.records[..<storage.head])
        }
    }

    /// Counter totals.
    public var counters: [String: Int] { storage.withLock { $0.counters } }

    /// Scroll smoothness per page.
    public var scroll: [String: ScrollStats] { storage.withLock { $0.scroll } }

    /// Stats per kind, and per kind and page (`kind@page`).
    public var stats: [String: TelemetryStats] {
        var samples: [String: [Double]] = [:]
        for record in records {
            guard let sample = record.durationMs ?? record.value else { continue }
            samples[record.kind, default: []].append(sample)
            if let page = record.page { samples["\(record.kind)@\(page)", default: []].append(sample) }
        }
        return samples.compactMapValues(TelemetryStats.init)
    }

    /// Everything, for the export file.
    public func export(environment: [String: String] = [:], now: Date = .now) -> TelemetryExport {
        TelemetryExport(exportedAt: now, environment: environment, counters: counters, stats: stats, scroll: scroll, records: records)
    }

    /// The export as pretty-printed JSON.
    public func exportJSON(environment: [String: String] = [:], now: Date = .now) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(export(environment: environment, now: now))
    }
}
