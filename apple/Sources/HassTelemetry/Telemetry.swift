import Foundation
import os

/// The app's performance telemetry (pattern: `.agents/patterns/telemetry.md`).
///
/// Two sinks, one call:
/// - **Signposts** (`OSSignposter`, subsystem ``subsystem``) for Instruments and for XCUITest
///   `XCTOSSignpostMetric` measurements. Always on; they cost almost nothing when nothing is recording.
/// - **The in-app log** (``TelemetryLog``): counters and recent samples the debug Performance screen shows and
///   exports. Recording is cheap but not free, so it runs only while ``isEnabled`` (Debug builds, or
///   `FENTON_TELEMETRY=1`, or the Performance screen's switch).
///
/// Every API is safe from any thread.
public enum Telemetry {
    // MARK: - Configuration

    /// The signpost subsystem. UI tests measure intervals with this subsystem and ``category``.
    public static let subsystem = "com.sfenton.home"
    /// The signpost category.
    public static let category = "Performance"

    /// The signposter every interval goes through.
    public static let signposter = OSSignposter(subsystem: subsystem, category: category)

    /// Signpost and log names. UI tests measure these by name, so they never change casually.
    public enum Name {
        /// A batch of live entity updates applied to the store (count in the message).
        public static let entityUpdate: StaticString = "EntityUpdate"
        /// A page from first appearance until its content gate shows content.
        public static let contentReady: StaticString = "ContentReady"
        /// An image fetched from the network (including a revalidation).
        public static let imageFetch: StaticString = "ImageFetch"
        /// An image decoded and downsampled.
        public static let imageDecode: StaticString = "ImageDecode"
        /// A service call from send until Home Assistant answers.
        public static let serviceCall: StaticString = "ServiceCall"
        /// An optimistic value from commit until Home Assistant confirms it.
        public static let optimisticConfirm: StaticString = "OptimisticConfirm"
        /// One scroll gesture on a page, from drag start until the deceleration stops.
        public static let scroll: StaticString = "Scroll"
        /// A frame that missed its deadline.
        public static let hitch: StaticString = "Hitch"
    }

    /// `UserDefaults` key for the Performance screen's recording switch.
    public static let enabledDefaultsKey = "telemetry.enabled"

    private static let enabledState = OSAllocatedUnfairLock<Bool>(initialState: Telemetry.defaultEnabled())

    /// Whether the in-app log records. Signposts are emitted either way.
    public static var isEnabled: Bool {
        get { enabledState.withLock { $0 } }
        set {
            enabledState.withLock { $0 = newValue }
            UserDefaults.standard.set(newValue, forKey: enabledDefaultsKey)
        }
    }

    /// Debug builds record by default; Release records only when asked (environment or the saved switch).
    static func defaultEnabled(environment: [String: String] = ProcessInfo.processInfo.environment,
                               defaults: UserDefaults = .standard) -> Bool {
        if let value = environment["FENTON_TELEMETRY"] { return value == "1" }
        if defaults.object(forKey: enabledDefaultsKey) != nil { return defaults.bool(forKey: enabledDefaultsKey) }
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    /// The shared in-app log.
    public static let log = TelemetryLog()

    // MARK: - Intervals

    /// A started interval. End it once with ``end(_:value:detail:)``.
    public struct Interval: Sendable {
        let name: StaticString
        let state: OSSignpostIntervalState
        let start: ContinuousClock.Instant
        let page: String?
    }

    /// Starts a signpost interval.
    /// - Parameters:
    ///   - name: One of ``Name``.
    ///   - page: The page it belongs to, for the log.
    ///   - message: Shown in Instruments.
    public static func begin(_ name: StaticString, page: String? = nil, _ message: String = "") -> Interval {
        let id = signposter.makeSignpostID()
        let state = signposter.beginInterval(name, id: id, "\(message, privacy: .public)")
        return Interval(name: name, state: state, start: .now, page: page)
    }

    /// Ends an interval and records its duration.
    /// - Parameters:
    ///   - interval: From ``begin(_:page:_:)``.
    ///   - value: An optional count that goes with it (entities changed, bytes).
    ///   - detail: A short note for the log (`hit`, `304`, an entity id).
    /// - Returns: The interval's duration in milliseconds.
    @discardableResult
    public static func end(_ interval: Interval, value: Double? = nil, detail: String? = nil) -> Double {
        signposter.endInterval(interval.name, interval.state, "\(detail ?? "", privacy: .public)")
        let ms = (ContinuousClock.now - interval.start).milliseconds
        if isEnabled {
            log.record(TelemetryRecord(kind: "\(interval.name)", page: interval.page, durationMs: ms, value: value, detail: detail))
        }
        return ms
    }

    /// Times a synchronous block.
    public static func measure<T>(_ name: StaticString, page: String? = nil, _ body: () throws -> T) rethrows -> T {
        let interval = begin(name, page: page)
        defer { end(interval) }
        return try body()
    }

    /// Records a point event (a cache hit, a hitch).
    /// - Parameters:
    ///   - name: One of ``Name``, or a counter name.
    ///   - page: The page it belongs to.
    ///   - value: A number that goes with it (hitch milliseconds).
    ///   - detail: A short note.
    public static func event(_ name: StaticString, page: String? = nil, value: Double? = nil, detail: String? = nil) {
        signposter.emitEvent(name, "\(detail ?? "", privacy: .public) \(value ?? 0)")
        if isEnabled {
            log.record(TelemetryRecord(kind: "\(name)", page: page, durationMs: nil, value: value, detail: detail))
        }
    }

    /// Adds to a named counter (cheap; no record is kept).
    public static func count(_ counter: String, by amount: Int = 1) {
        guard isEnabled else { return }
        log.increment(counter, by: amount)
    }
}

extension Duration {
    /// The duration in milliseconds.
    public var milliseconds: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) * 1000 + Double(attoseconds) / 1e15
    }
}
