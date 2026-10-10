import Foundation
import Security

/// What survives an app restart: the server and its refresh token.
public struct StoredCredentials: Codable, Sendable, Equatable {
    /// The server signed in to.
    public var server: HassServer
    /// Long-lived refresh token.
    public var refreshToken: String

    /// Creates stored credentials.
    public init(server: HassServer, refreshToken: String) {
        self.server = server
        self.refreshToken = refreshToken
    }
}

/// Persists ``StoredCredentials``. The production implementation is ``KeychainTokenStore``.
public protocol TokenStore: Sendable {
    /// Loads saved credentials, or `nil` when signed out.
    func load() -> StoredCredentials?
    /// Saves credentials, replacing any previous value.
    func save(_ credentials: StoredCredentials) throws
    /// Deletes saved credentials.
    func clear()
}

/// Keychain-backed ``TokenStore``. Items are this-device-only and readable after first unlock,
/// so background refreshes work but the token never migrates to another device via backup.
public struct KeychainTokenStore: TokenStore {
    private let service: String
    private let account = "credentials"
    private let accessGroup: String?

    /// Creates a store.
    /// - Parameters:
    ///   - service: Keychain service name.
    ///   - accessGroup: Shared access group (needed later for the watch app).
    public init(service: String = "com.sfenton.home.auth", accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    private var baseQuery: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }

    public func load() -> StoredCredentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(StoredCredentials.self, from: data)
    }

    public func save(_ credentials: StoredCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        clear()
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    public func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}

/// In-memory ``TokenStore`` for tests and previews.
public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: StoredCredentials?

    /// Creates a store, optionally pre-filled.
    public init(_ value: StoredCredentials? = nil) { self.value = value }

    public func load() -> StoredCredentials? { lock.withLock { value } }
    public func save(_ credentials: StoredCredentials) throws { lock.withLock { value = credentials } }
    public func clear() { lock.withLock { value = nil } }
}
