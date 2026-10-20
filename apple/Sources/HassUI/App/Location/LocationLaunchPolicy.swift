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
}
