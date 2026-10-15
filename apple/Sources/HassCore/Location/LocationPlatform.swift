import Foundation

/// Something the location platform reports to ``LocationReporter``.
public enum LocationPlatformEvent: Equatable, Sendable {
    /// The person changed the permission (or Settings did).
    case permissionChanged(LocationPermission)
    /// iOS reported a significant location change.
    case significantChange(LocationFix)
    /// The phone crossed a monitored zone boundary.
    case zone(ZoneEvent)
}

/// Why the platform could not produce a fix.
public enum LocationPlatformError: Error, Equatable, Sendable {
    /// No permission, Location Services off, or no fix in time.
    case unavailable
}

/// The Apple location frameworks behind one seam, so ``LocationReporter``'s rules run in tests without Core
/// Location. The app's implementation is ``CoreLocationPlatform`` (iOS); tests use a fake.
@MainActor
public protocol LocationPlatform: AnyObject {
    /// The current permission.
    var permission: LocationPermission { get }
    /// Receives the platform's events; the reporter sets it.
    var onEvent: (@MainActor (LocationPlatformEvent) -> Void)? { get set }
    /// Asks for While Using the App.
    func requestWhenInUse()
    /// Asks to upgrade to Always.
    func requestAlways()
    /// One fresh fix.
    func currentFix() async throws -> LocationFix
    /// Starts significant-change monitoring (wakes the app after about 500 m).
    func startSignificantChanges()
    /// Stops significant-change monitoring.
    func stopSignificantChanges()
    /// Watches exactly `regions`, replacing any others.
    func monitor(_ regions: [PlannedRegion]) async
    /// Stops watching every region.
    func stopMonitoring() async
}
