import Foundation
import HassCore

/// Where the feedback form files reports and keeps the GitHub token: GitHub and the Keychain, or the
/// fixture under `FENTON_FEEDBACK_FIXTURE` (`1` starts connected, `connect` starts without a token).
struct FeedbackServices: Sendable {
    var filer: any FeedbackFiling
    var store: any GitHubAccessStore

    /// The services for this process, resolved once so a fixture's token survives closing the form.
    static let current = resolve(ProcessInfo.processInfo.environment)

    /// Resolves services from launch environment variables.
    static func resolve(_ environment: [String: String]) -> FeedbackServices {
        switch environment["FENTON_FEEDBACK_FIXTURE"] {
        case "1":
            FeedbackServices(filer: FeedbackFixtureFiler(delay: .milliseconds(400)), store: InMemoryGitHubAccessStore(FeedbackFixtureFiler.access))
        case "connect":
            FeedbackServices(filer: FeedbackFixtureFiler(delay: .milliseconds(400)), store: InMemoryGitHubAccessStore())
        default:
            FeedbackServices(filer: GitHubFeedbackClient(), store: KeychainGitHubAccessStore())
        }
    }

    /// A token handed to a Debug build at launch (`FENTON_GITHUB_TOKEN`), for a live end-to-end run on a
    /// simulator without typing a real token into the UI (typed text lands in test logs). Release builds
    /// ignore it.
    static var launchToken: String? {
        #if DEBUG
        ProcessInfo.processInfo.environment["FENTON_GITHUB_TOKEN"].flatMap { $0.isEmpty ? nil : $0 }
        #else
        nil
        #endif
    }
}
