import Foundation
import Security

/// One `mobile_app` registration: the webhook Home Assistant issued to this phone for one user on one server.
public struct PushRegistration: Codable, Equatable, Sendable {
    /// The server registered with.
    public var server: HassServer
    /// The Home Assistant user the registration belongs to.
    public var userID: String
    /// The webhook id; it addresses the registration, so it is kept in the Keychain like a credential.
    public var webhookID: String

    /// Creates a registration.
    public init(server: HassServer, userID: String, webhookID: String) {
        self.server = server
        self.userID = userID
        self.webhookID = webhookID
    }

    /// `POST` target for webhook commands.
    public var webhookURL: URL { server.url("/api/webhook/\(webhookID)") }
}

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

/// Keychain-backed ``PushRegistrationStore``: one this-device-only item holding every user's webhook, readable
/// after first unlock so a notification button works from the lock screen.
public final class KeychainPushRegistrationStore: PushRegistrationStore, @unchecked Sendable {
    private let service: String
    private let account = "registrations"
    private let lock = NSLock()

    /// Creates a store.
    /// - Parameter service: Keychain service name.
    public init(service: String = "com.sfenton.home.push") {
        self.service = service
    }

    public func registration(server: HassServer, userID: String) -> PushRegistration? {
        lock.withLock { read().registration(server: server, userID: userID) }
    }

    public func save(_ registration: PushRegistration) {
        update { $0.save(registration) }
    }

    public func remove(server: HassServer, userID: String) {
        update { $0.remove(server: server, userID: userID) }
    }

    public var active: PushRegistration? { lock.withLock { read().active } }

    public func setActive(_ registration: PushRegistration?) {
        update { $0.active = registration }
    }

    // MARK: - Keychain

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    private func update(_ change: (inout PushRegistrationList) -> Void) {
        lock.withLock {
            var list = read()
            change(&list)
            write(list)
        }
    }

    private func read() -> PushRegistrationList {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return PushRegistrationList()
        }
        return (try? JSONDecoder().decode(PushRegistrationList.self, from: data)) ?? PushRegistrationList()
    }

    private func write(_ list: PushRegistrationList) {
        SecItemDelete(baseQuery as CFDictionary)
        guard let data = try? JSONEncoder().encode(list) else { return }
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }
}

/// In-memory ``PushRegistrationStore`` for tests and previews.
public final class InMemoryPushRegistrationStore: PushRegistrationStore, @unchecked Sendable {
    private let lock = NSLock()
    private var list = PushRegistrationList()

    /// Creates a store, optionally pre-filled.
    public init(_ registrations: [PushRegistration] = [], active: PushRegistration? = nil) {
        list = PushRegistrationList(registrations: registrations, active: active)
    }

    public func registration(server: HassServer, userID: String) -> PushRegistration? {
        lock.withLock { list.registration(server: server, userID: userID) }
    }

    public func save(_ registration: PushRegistration) { lock.withLock { list.save(registration) } }
    public func remove(server: HassServer, userID: String) { lock.withLock { list.remove(server: server, userID: userID) } }
    public var active: PushRegistration? { lock.withLock { list.active } }
    public func setActive(_ registration: PushRegistration?) { lock.withLock { list.active = registration } }
}
