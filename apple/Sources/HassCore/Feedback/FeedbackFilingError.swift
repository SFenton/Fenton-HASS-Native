import Foundation

/// A failed GitHub call, phrased for the person (never GitHub's own text, which can carry request details).
public enum FeedbackFilingError: LocalizedError, Equatable, Sendable {
    /// 401: the token is wrong, expired or revoked.
    case tokenRejected
    /// 403/404 on the repository: the token can't reach the request repository.
    case noRepositoryAccess
    /// 403 on creating the issue: the token lacks Issues write.
    case noIssueAccess
    /// The upload of one attachment was refused.
    case attachmentRejected(String)
    /// 403/429 with GitHub's rate-limit headers.
    case rateLimited
    /// 5xx.
    case unavailable
    case httpStatus(Int)
    case network
    /// The answer wasn't what GitHub documents.
    case unexpectedResponse

    public var errorDescription: String? {
        switch self {
        case .tokenRejected:
            "GitHub didn't accept the access token. It may have expired; add a new one."
        case .noRepositoryAccess:
            "The access token can't reach the \(FeedbackDestination.requests.name) repository. Create one with access to it."
        case .noIssueAccess:
            "The access token can't create issues. Give it Issues: Read and write."
        case let .attachmentRejected(name):
            "GitHub didn't accept \(name). Remove it and try again."
        case .rateLimited:
            "GitHub is limiting requests right now. Try again in a few minutes."
        case .unavailable:
            "GitHub is unavailable right now. Try again in a few minutes."
        case let .httpStatus(code):
            "GitHub returned an error (\(code)). Try again."
        case .network:
            "Couldn't reach GitHub. Check your connection and try again."
        case .unexpectedResponse:
            "GitHub sent an unexpected answer. Try again."
        }
    }

    /// Whether the person should replace their token.
    public var needsNewToken: Bool {
        switch self {
        case .tokenRejected, .noRepositoryAccess, .noIssueAccess: true
        default: false
        }
    }

    /// Maps a non-success status.
    ///
    /// - Parameters:
    ///   - status: HTTP status.
    ///   - rateLimitRemaining: `x-ratelimit-remaining` header.
    ///   - onRepository: Whether the call read the repository (403/404 means no access to it).
    /// - Returns: The error.
    public static func forStatus(_ status: Int, rateLimitRemaining: String?, onRepository: Bool = false) -> FeedbackFilingError {
        switch status {
        case 401: return .tokenRejected
        case 403 where rateLimitRemaining == "0", 429: return .rateLimited
        case 403, 404: return onRepository ? .noRepositoryAccess : .noIssueAccess
        case 500...599: return .unavailable
        default: return .httpStatus(status)
        }
    }
}
