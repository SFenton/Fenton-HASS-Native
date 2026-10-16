import Foundation
import HassCore

/// A scripted ``LocationPlatform``: records what the reporter asked for and hands out queued fixes.
@MainActor
public final class FakeLocationPlatform: LocationPlatform {
    public var permission: LocationPermission
    public var onEvent: (@MainActor (LocationPlatformEvent) -> Void)?
    public var fixes: [LocationFix] = []
    public var calls: [String] = []
    public var monitored: [PlannedRegion] = []

    public init(_ permission: LocationPermission) { self.permission = permission }

    public func requestWhenInUse() { calls.append("whenInUse") }
    public func requestAlways() { calls.append("always") }
    public func currentFix() async throws -> LocationFix {
        guard !fixes.isEmpty else { throw LocationPlatformError.unavailable }
        return fixes.removeFirst()
    }
    public func startSignificantChanges() { calls.append("startSignificant") }
    public func stopSignificantChanges() { calls.append("stopSignificant") }
    public func monitor(_ regions: [PlannedRegion]) async {
        calls.append("monitor \(regions.count)")
        monitored = regions
    }
    public func stopMonitoring() async {
        calls.append("stopMonitoring")
        monitored = []
    }
}
