import Foundation

/// Persists ``GitHubAccess``. The production implementation is ``KeychainGitHubAccessStore``.
public protocol GitHubAccessStore: Sendable {
    /// Saved access, or nil.
    func load() -> GitHubAccess?
    /// Saves access, replacing any previous value.
    func save(_ access: GitHubAccess) throws
    /// Deletes saved access.
    func clear()
}
