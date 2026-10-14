import Foundation

/// The private GitHub repository reports are filed in, which the triage agent on the MacBook works from
/// (`.agents/workflow/triage-agent.md`).
public struct FeedbackDestination: Sendable, Equatable {
    public var owner: String
    public var name: String

    /// Creates a destination.
    public init(owner: String, name: String) {
        self.owner = owner
        self.name = name
    }

    /// `SFenton/fenton-hass-requests`.
    public static let requests = FeedbackDestination(owner: "SFenton", name: "fenton-hass-requests")

    /// `owner/name`.
    public var slug: String { "\(owner)/\(name)" }

    /// GitHub's pre-filled "new fine-grained token" page: one year, Issues read and write. GitHub has no
    /// parameter for the repository, so the person picks it (only this one) on the page.
    public var tokenCreationURL: URL {
        var components = URLComponents(string: "https://github.com/settings/personal-access-tokens/new")!
        components.queryItems = [
            URLQueryItem(name: "name", value: "Fenton Home feedback"),
            URLQueryItem(name: "description", value: "Files Report an Issue and Request a Feature from the Fenton Home app into \(slug)."),
            URLQueryItem(name: "target_name", value: owner),
            URLQueryItem(name: "expires_in", value: "365"),
            URLQueryItem(name: "issues", value: "write"),
        ]
        return components.url!
    }
}
