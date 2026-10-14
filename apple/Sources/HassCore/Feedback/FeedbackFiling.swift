import Foundation

/// Files reports. ``GitHubFeedbackClient`` talks to GitHub; ``FeedbackFixtureFiler`` answers UI tests.
public protocol FeedbackFiling: Sendable {
    /// Checks a token against the request repository.
    /// - Returns: Access to save: the token, its user and the repository id.
    func verify(token: String) async throws -> GitHubAccess
    /// Uploads one attachment and returns its GitHub URL.
    func upload(_ attachment: FeedbackAttachment, access: GitHubAccess) async throws -> URL
    /// Creates the issue.
    func createIssue(_ issue: FeedbackIssue, access: GitHubAccess) async throws -> FiledIssue
}
