import Foundation

/// A verified GitHub access token and what it was verified against.
public struct GitHubAccess: Codable, Sendable, Equatable {
    /// The token. Never logged, shown or included in a report.
    public var token: String
    /// The GitHub user the token belongs to, shown as "Sending as @login".
    public var login: String
    /// The request repository's numeric id (user-attachment uploads need it).
    public var repositoryID: Int

    /// Creates access.
    public init(token: String, login: String, repositoryID: Int) {
        self.token = token
        self.login = login
        self.repositoryID = repositoryID
    }
}
