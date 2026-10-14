#if DEBUG
import Foundation

/// A ``FeedbackFiling`` that never reaches GitHub, for UI tests, the gallery and previews
/// (`FENTON_FEEDBACK_FIXTURE`).
///
/// - `fixture-token` verifies as `fixture-user`; any other token is rejected.
/// - Uploads answer `https://github.com/user-attachments/assets/fixture-<n>`.
/// - Issues are filed as #1, except a title containing `fixture-failed` (GitHub unavailable) or
///   `fixture-token` (token rejected).
public final class FeedbackFixtureFiler: FeedbackFiling, @unchecked Sendable {
    /// The token the fixture accepts.
    public static let token = "fixture-token"
    /// Access as the fixture's verified user.
    public static let access = GitHubAccess(token: token, login: "fixture-user", repositoryID: 1)

    private let lock = NSLock()
    private var issues: [FeedbackIssue] = []
    private var uploadCount = 0
    private let delay: Duration

    /// Creates a fixture.
    /// - Parameter delay: Pause before each answer, so progress states are visible.
    public init(delay: Duration = .zero) {
        self.delay = delay
    }

    /// Issues created so far.
    public var createdIssues: [FeedbackIssue] { lock.withLock { issues } }

    public func verify(token: String) async throws -> GitHubAccess {
        try await Task.sleep(for: delay)
        guard token.trimmingCharacters(in: .whitespacesAndNewlines) == Self.token else {
            throw FeedbackFilingError.tokenRejected
        }
        return Self.access
    }

    public func upload(_ attachment: FeedbackAttachment, access: GitHubAccess) async throws -> URL {
        try await Task.sleep(for: delay)
        let count = lock.withLock { uploadCount += 1; return uploadCount }
        return URL(string: "https://github.com/user-attachments/assets/fixture-\(count)")!
    }

    public func createIssue(_ issue: FeedbackIssue, access: GitHubAccess) async throws -> FiledIssue {
        try await Task.sleep(for: delay)
        if issue.title.contains("fixture-failed") { throw FeedbackFilingError.unavailable }
        if issue.title.contains("fixture-token") { throw FeedbackFilingError.tokenRejected }
        lock.withLock { issues.append(issue) }
        return FiledIssue(number: 1, url: URL(string: "https://github.com/\(FeedbackDestination.requests.slug)/issues/1")!)
    }
}
#endif
