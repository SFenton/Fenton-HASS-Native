import Foundation

/// The stored list and active pointer.
struct MobileAppRegistrationList: Codable, Equatable {
    var registrations: [MobileAppRegistration] = []
    var active: MobileAppRegistration?

    func registration(server: HassServer, userID: String) -> MobileAppRegistration? {
        registrations.first { $0.server == server && $0.userID == userID }
    }

    mutating func save(_ registration: MobileAppRegistration) {
        registrations.removeAll { $0.server == registration.server && $0.userID == registration.userID }
        registrations.append(registration)
    }

    mutating func remove(server: HassServer, userID: String) {
        registrations.removeAll { $0.server == server && $0.userID == userID }
        if active?.server == server, active?.userID == userID { active = nil }
    }
}
