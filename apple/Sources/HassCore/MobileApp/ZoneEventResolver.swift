import Foundation

/// A monitored zone boundary crossing, by zone entity id.
public enum ZoneEvent: Equatable, Sendable {
    case entered(String)
    case exited(String)

    /// The trigger the update is reported with.
    public var trigger: LocationTrigger {
        switch self {
        case .entered: .regionEntered
        case .exited: .regionExited
        }
    }
}

/// Decides the `location_name` sent with a zone event, so GPS wobble at a boundary cannot flip a person back.
///
/// - Enter: `home` for the home zone, otherwise the zone's name (Home Assistant's own state for a tracker inside
///   that zone).
/// - Exit: `not_home` only when the fix is outside every known non-passive zone by more than its accuracy;
///   otherwise nothing, and Home Assistant computes the zone from the coordinates.
public struct ZoneEventResolver: Sendable {
    /// Every zone from `get_zones`.
    public var zones: [HAZone]

    /// Creates a resolver over `zones`.
    public init(zones: [HAZone]) {
        self.zones = zones
    }

    /// The `location_name` for `event`, or nil to let Home Assistant decide.
    /// - Parameters:
    ///   - event: The crossing.
    ///   - fix: The position taken for it; an exit without a valid fix sends no name.
    public func locationName(for event: ZoneEvent, fix: LocationFix?) -> String? {
        switch event {
        case .entered(let id):
            guard let zone = zones.first(where: { $0.entityID == id }), !zone.isPassive else { return nil }
            return zone.isHome ? "home" : zone.friendlyName
        case .exited:
            guard let fix, fix.isValid else { return nil }
            let active = zones.filter { !$0.isPassive }
            let clearOfAll = active.allSatisfy { $0.distanceOutside(fix) > fix.horizontalAccuracy }
            return clearOfAll ? "not_home" : nil
        }
    }
}
