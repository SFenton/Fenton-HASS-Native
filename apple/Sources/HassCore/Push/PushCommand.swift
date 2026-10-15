import Foundation

/// A silent command a background push carries (contract v1, rule 3).
public enum PushCommand: Equatable, Sendable {
    /// Remove delivered notifications with this tag.
    case clearNotification(tag: String)
    /// A command this version ignores (`request_location_update`, `update_widgets`, `clear_badge`, ...).
    case unsupported(String)
}
