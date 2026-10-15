import Foundation

/// The app's `mobile_app` identity (contract v1, rule 2).
public enum PushApp {
    /// `app_id`: the app's bundle identifier.
    public static let appID = "com.sfenton.home"
    /// `app_name`.
    public static let appName = "Fenton Home"
    /// Suffix on every `device_name`, so Home Assistant names this app's notify service apart from the official
    /// companion app's on the same phone (`notify.mobile_app_<device>_fenton`).
    public static let deviceNameSuffix = " · Fenton"
}
