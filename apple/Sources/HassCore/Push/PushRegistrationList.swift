import Foundation

/// The stored list and active pointer.
struct PushRegistrationList: Codable, Equatable {
    var registrations: [PushRegistration] = []
    var active: PushRegistration?

    func registration(server: HassServer, userID: String) -> PushRegistration? {
        registrations.first { $0.server == server && $0.userID == userID }
    }

    mutating func save(_ registration: PushRegistration) {
        registrations.removeAll { $0.server == registration.server && $0.userID == registration.userID }
        registrations.append(registration)
    }

    mutating func remove(server: HassServer, userID: String) {
        registrations.removeAll { $0.server == server && $0.userID == userID }
        if active?.server == server, active?.userID == userID { active = nil }
    }
}
