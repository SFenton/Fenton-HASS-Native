import Foundation

/// Whether this launch reports location (`.agents/platforms/apple/location.md`).
public enum LocationLaunchPolicy {
    /// Phones only: an iPad is never a presence device, and never shows the permission screen ("This phone").
    /// Debug UI journeys (a test token, a reset launch, or the component gallery) keep it off unless
    /// `FENTON_LOCATION=1`, so a journey never meets the permission alert unasked.
    /// - Parameters:
    ///   - environment: The launch environment.
    ///   - isPresenceDevice: Whether this device reports location (``LocationReporter/deviceIsPresenceDevice``).
    public static func isEnabled(environment: [String: String] = ProcessInfo.processInfo.environment,
                                 isPresenceDevice: Bool) -> Bool {
        guard isPresenceDevice else { return false }
        #if DEBUG
        if environment["FENTON_LOCATION"] == "1" { return true }
        let journey = ["FENTON_HASS_TOKEN", "FENTON_UITEST_RESET", "FENTON_GALLERY"].contains { !(environment[$0] ?? "").isEmpty }
        return !journey
        #else
        return true
        #endif
    }

    /// `UserDefaults` key that arms reporting on this install.
    public static let armedKey = "location.reportingArmed"

    /// Whether this install sends location updates: ``armedKey``, which the Account sheet's toggle sets and which is
    /// off by default (shadow mode must never move a person; `presence-inventory.md`). Debug builds take
    /// `FENTON_LOCATION_REPORT=1` (or `0`) at launch as an override, which also persists so the toggle shows it.
    /// - Parameters:
    ///   - environment: The launch environment.
    ///   - defaults: Where the armed flag persists.
    public static func isReportingArmed(environment: [String: String] = ProcessInfo.processInfo.environment,
                                        defaults: UserDefaults = .standard) -> Bool {
        #if DEBUG
        switch environment["FENTON_LOCATION_REPORT"] {
        case "1": defaults.set(true, forKey: armedKey)
        case "0": defaults.removeObject(forKey: armedKey)
        default: break
        }
        #endif
        return defaults.bool(forKey: armedKey)
    }
}
