import Foundation
import Security

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
