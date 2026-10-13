import Foundation
import Security

/// Keychain-backed ``GitHubAccessStore``.
///
/// Unlike the Home Assistant refresh token (this device only), the GitHub token syncs through iCloud
/// Keychain so it is entered once for all of a person's devices: it only reaches issues in one private
/// repository, and iCloud Keychain is end-to-end encrypted.
public struct KeychainGitHubAccessStore: GitHubAccessStore {
    private let service: String
    private let account = "feedback"

    /// Creates a store.
    /// - Parameter service: Keychain service name.
    public init(service: String = "com.sfenton.home.github") {
        self.service = service
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
    }

    public func load() -> GitHubAccess? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(GitHubAccess.self, from: data)
    }

    public func save(_ access: GitHubAccess) throws {
        let data = try JSONEncoder().encode(access)
        clear()
        var query = baseQuery
        query[kSecAttrSynchronizable as String] = kCFBooleanTrue
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }

    public func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
