import Foundation

/// Drops fixes not worth sending, so a busy hour of significant changes doesn't flood Home Assistant.
///
/// - Invalid fixes are always dropped.
/// - Zone events always pass: the crossing itself is the news, whatever the accuracy.
/// - Otherwise fixes worse than 200 m are dropped.
/// - A fix within 10 m and 30 s of the last one sent is a duplicate and dropped, unless the person asked for it
///   (``LocationTrigger/manual``).
public struct LocationFixFilter: Sendable {
    /// Worst accepted horizontal accuracy, in meters.
    public static let maximumAccuracy: Double = 200
    /// Fixes closer together in time than this may be duplicates.
    public static let duplicateInterval: TimeInterval = 30
    /// Fixes closer together than this, within ``duplicateInterval``, are duplicates.
    public static let duplicateDistance: Double = 10

    /// The last fix let through.
    public private(set) var lastAdmitted: LocationFix?

    /// Creates a filter with no history.
    public init() {}

    /// Whether to send `fix`; a fix let through becomes the reference for the next duplicate check.
    public mutating func admit(_ fix: LocationFix, trigger: LocationTrigger) -> Bool {
        guard fix.isValid else { return false }
        if !trigger.isZoneEvent {
            guard fix.horizontalAccuracy <= Self.maximumAccuracy else { return false }
            if trigger != .manual, let last = lastAdmitted,
               abs(fix.timestamp.timeIntervalSince(last.timestamp)) < Self.duplicateInterval,
               fix.distance(to: last) < Self.duplicateDistance {
                return false
            }
        }
        lastAdmitted = fix
        return true
    }

    /// Forgets the history (sign-out, or a new registration).
    public mutating func reset() {
        lastAdmitted = nil
    }
}
