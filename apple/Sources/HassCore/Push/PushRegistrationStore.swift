import Foundation

/// Keeps one webhook per Home Assistant user, so signing in again as the same person reuses the phone's
/// `mobile_app` device instead of adding another (contract v1, rule 2). The production store is
/// ``KeychainPushRegistrationStore``.
public protocol PushRegistrationStore: Sendable {
    /// The saved registration for a user, if any.
    func registration(server: HassServer, userID: String) -> PushRegistration?
    /// Saves a registration, replacing the user's previous one.
    func save(_ registration: PushRegistration)
    /// Forgets a user's registration (Home Assistant deleted it).
    func remove(server: HassServer, userID: String)
    /// The registration of the user signed in now, used to answer notification buttons.
    var active: PushRegistration? { get }
    /// Marks the signed-in user's registration; nil after sign-out.
    func setActive(_ registration: PushRegistration?)
}
