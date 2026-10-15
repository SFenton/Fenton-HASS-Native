import Foundation

/// A circular region the phone asks iOS to watch for one zone.
public struct PlannedRegion: Equatable, Sendable, Identifiable {
    /// The zone's entity id, used as the monitor's condition identifier.
    public var id: String
    /// Center latitude.
    public var latitude: Double
    /// Center longitude.
    public var longitude: Double
    /// Radius in meters, after padding.
    public var radius: Double

    /// Creates a region.
    public init(id: String, latitude: Double, longitude: Double, radius: Double) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
    }
}

/// Picks the zones to watch: iOS monitors at most 20 regions per app, so watch the nearest ones.
///
/// Rules (matching the official app): the home zone is always watched; passive zones never are (they cannot set
/// anyone's state); the rest are the nearest to the last fix; and radii below 100 m are padded to 100 m, the size
/// iOS reports reliably.
public struct ZonePlanner: Sendable {
    /// The most regions iOS monitors for one app.
    public static let regionLimit = 20
    /// The smallest radius iOS reports crossings for reliably.
    public static let minimumRadius: Double = 100

    /// How many regions to plan.
    public var limit: Int

    /// Creates a planner.
    public init(limit: Int = ZonePlanner.regionLimit) {
        self.limit = limit
    }

    /// The regions to monitor.
    /// - Parameters:
    ///   - zones: Every zone from `get_zones`.
    ///   - fix: The last known position; without one, zones keep Home Assistant's order.
    public func plan(_ zones: [HAZone], near fix: LocationFix?) -> [PlannedRegion] {
        guard limit > 0 else { return [] }
        let home = zones.first(where: \.isHome)
        var others = zones.filter { !$0.isHome && !$0.isPassive }
        if let fix, fix.isValid {
            // Stable for equal distances, so a replan with the same inputs never reshuffles conditions.
            others = others.enumerated().sorted { lhs, rhs in
                let left = lhs.element.distanceOutside(fix), right = rhs.element.distanceOutside(fix)
                return left == right ? lhs.offset < rhs.offset : left < right
            }.map(\.element)
        }
        let chosen = (home.map { [$0] } ?? []) + others.prefix(limit - (home == nil ? 0 : 1))
        return chosen.map {
            PlannedRegion(id: $0.entityID, latitude: $0.latitude, longitude: $0.longitude,
                          radius: max($0.radius, Self.minimumRadius))
        }
    }
}
