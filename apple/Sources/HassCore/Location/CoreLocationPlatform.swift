#if os(iOS)
import CoreLocation
import Foundation

/// ``LocationPlatform`` on Core Location: `CLLocationManager` for permission, one-shot fixes and significant
/// changes, and iOS 17's `CLMonitor` circular conditions for zones.
///
/// Zones are added assuming the phone is outside them, so the first evaluation reports an entry only for the zone
/// the phone is in and never a burst of exits. `CLMonitor` keeps its conditions across launches under one name, and
/// a relaunch for a zone event delivers that event once the monitor is opened again.
@MainActor
public final class CoreLocationPlatform: NSObject, LocationPlatform {
    public var onEvent: (@MainActor (LocationPlatformEvent) -> Void)?

    private let manager = CLLocationManager()
    private var zoneMonitor: CLMonitor?
    private var zoneEvents: Task<Void, Never>?
    private var fixWaiters: [CheckedContinuation<LocationFix, any Error>] = []

    /// The `CLMonitor` name; conditions persist under it.
    static let monitorName = "FentonHomeZones"

    /// Creates the platform; create it on the main thread, as `CLLocationManager` needs a run loop.
    public override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    public var permission: LocationPermission {
        Self.permission(manager.authorizationStatus, accuracy: manager.accuracyAuthorization)
    }

    public func requestWhenInUse() { manager.requestWhenInUseAuthorization() }

    public func requestAlways() { manager.requestAlwaysAuthorization() }

    public func currentFix() async throws -> LocationFix {
        try await withCheckedThrowingContinuation { continuation in
            fixWaiters.append(continuation)
            if fixWaiters.count == 1 { manager.requestLocation() }
        }
    }

    public func startSignificantChanges() {
        guard CLLocationManager.significantLocationChangeMonitoringAvailable() else { return }
        manager.startMonitoringSignificantLocationChanges()
    }

    public func stopSignificantChanges() { manager.stopMonitoringSignificantLocationChanges() }

    public func monitor(_ regions: [PlannedRegion]) async {
        let monitor = await openMonitor()
        let wanted = Dictionary(uniqueKeysWithValues: regions.map { ($0.id, $0) })
        for id in await monitor.identifiers where wanted[id] == nil {
            await monitor.remove(id)
        }
        for region in regions {
            let condition = CLMonitor.CircularGeographicCondition(
                center: CLLocationCoordinate2D(latitude: region.latitude, longitude: region.longitude), radius: region.radius
            )
            // Re-adding an unchanged condition would reset its state; leave it alone.
            if let existing = await monitor.record(for: region.id)?.condition as? CLMonitor.CircularGeographicCondition,
               existing.center.latitude == region.latitude, existing.center.longitude == region.longitude,
               existing.radius == region.radius {
                continue
            }
            await monitor.add(condition, identifier: region.id, assuming: .unsatisfied)
        }
    }

    public func stopMonitoring() async {
        guard let monitor = zoneMonitor else { return }
        for id in await monitor.identifiers { await monitor.remove(id) }
    }

    // MARK: - Monitor

    private func openMonitor() async -> CLMonitor {
        if let zoneMonitor { return zoneMonitor }
        let monitor = await CLMonitor(Self.monitorName)
        zoneMonitor = monitor
        zoneEvents = Task { [weak self] in
            do {
                for try await event in await monitor.events {
                    switch event.state {
                    case .satisfied: self?.onEvent?(.zone(.entered(event.identifier)))
                    case .unsatisfied: self?.onEvent?(.zone(.exited(event.identifier)))
                    default: break
                    }
                }
            } catch {
                // The sequence ends only when the monitor is torn down.
            }
        }
        return monitor
    }

    // MARK: - Fixes

    private func deliver(_ fix: LocationFix) {
        guard !fixWaiters.isEmpty else {
            onEvent?(.significantChange(fix))
            return
        }
        let waiters = fixWaiters
        fixWaiters = []
        waiters.forEach { $0.resume(returning: fix) }
    }

    private func failWaiters() {
        let waiters = fixWaiters
        fixWaiters = []
        waiters.forEach { $0.resume(throwing: LocationPlatformError.unavailable) }
    }

    /// Maps Core Location's permission onto ``LocationPermission``.
    nonisolated static func permission(_ status: CLAuthorizationStatus, accuracy: CLAccuracyAuthorization) -> LocationPermission {
        let authorization: LocationPermission.Authorization = switch status {
        case .authorizedAlways: .always
        case .authorizedWhenInUse: .whenInUse
        case .denied: .denied
        case .restricted: .restricted
        default: .notDetermined
        }
        return LocationPermission(authorization: authorization, isPrecise: accuracy == .fullAccuracy)
    }
}

extension CoreLocationPlatform: CLLocationManagerDelegate {
    public nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let permission = Self.permission(manager.authorizationStatus, accuracy: manager.accuracyAuthorization)
        Task { @MainActor in self.onEvent?(.permissionChanged(permission)) }
    }

    public nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let fix = LocationFix(location)
        Task { @MainActor in self.deliver(fix) }
    }

    public nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        Task { @MainActor in self.failWaiters() }
    }
}

public extension LocationFix {
    /// A fix from a Core Location reading.
    init(_ location: CLLocation) {
        self.init(
            latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
            horizontalAccuracy: location.horizontalAccuracy, altitude: location.altitude,
            verticalAccuracy: location.verticalAccuracy, speed: location.speed, course: location.course,
            timestamp: location.timestamp
        )
    }
}
#endif
