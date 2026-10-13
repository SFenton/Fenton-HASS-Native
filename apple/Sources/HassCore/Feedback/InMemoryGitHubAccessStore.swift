import Foundation

/// In-memory ``GitHubAccessStore`` for tests, previews and the UI-test fixture.
public final class InMemoryGitHubAccessStore: GitHubAccessStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: GitHubAccess?

    /// Creates a store, optionally pre-filled.
    public init(_ value: GitHubAccess? = nil) { self.value = value }

    public func load() -> GitHubAccess? { lock.withLock { value } }
    public func save(_ access: GitHubAccess) throws { lock.withLock { value = access } }
    public func clear() { lock.withLock { value = nil } }
}
