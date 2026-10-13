import Foundation

/// Files reports in the request repository through GitHub's REST API.
///
/// Calls: `GET /user` and `GET /repos/{owner}/{repo}` to verify a token, `POST
/// uploads.github.com/user-attachments/assets` for media (the endpoint FestivalNativeApps' tracker uses
/// for evidence), `POST /repos/{owner}/{repo}/issues` for the issue. This is the app's only non-Home
/// Assistant network path, and it runs only when someone presses Save Token or Submit.
public struct GitHubFeedbackClient: FeedbackFiling {
    private let destination: FeedbackDestination
    private let transport: any FeedbackHTTPTransport
    private let api = URL(string: "https://api.github.com")!
    private let uploads = URL(string: "https://uploads.github.com/user-attachments/assets")!

    /// Creates a client.
    public init(destination: FeedbackDestination = .requests, transport: any FeedbackHTTPTransport = URLSessionFeedbackTransport()) {
        self.destination = destination
        self.transport = transport
    }

    public func verify(token: String) async throws -> GitHubAccess {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let user = try await json(request("GET", api.appending(path: "user"), token: token))
        let repo = try await json(request("GET", api.appending(path: "repos/\(destination.slug)"), token: token), onRepository: true)
        guard let login = user["login"] as? String, let id = repo["id"] as? Int else {
            throw FeedbackFilingError.unexpectedResponse
        }
        return GitHubAccess(token: token, login: login, repositoryID: id)
    }

    public func upload(_ attachment: FeedbackAttachment, access: GitHubAccess) async throws -> URL {
        var components = URLComponents(url: uploads, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "name", value: attachment.filename),
            URLQueryItem(name: "content_type", value: attachment.mimeType),
            URLQueryItem(name: "repository_id", value: String(access.repositoryID)),
        ]
        guard let data = try? Data(contentsOf: attachment.fileURL) else {
            throw FeedbackFilingError.attachmentRejected(attachment.filename)
        }
        var upload = request("POST", components.url!, token: access.token)
        upload.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        upload.httpBody = data
        upload.timeoutInterval = 300
        let body: [String: Any]
        do {
            body = try await json(upload)
        } catch FeedbackFilingError.httpStatus(let code) where (400..<500).contains(code) {
            throw FeedbackFilingError.attachmentRejected(attachment.filename)
        }
        guard let text = body["url"] as? String, let url = URL(string: text), url.scheme == "https" else {
            throw FeedbackFilingError.unexpectedResponse
        }
        return url
    }

    public func createIssue(_ issue: FeedbackIssue, access: GitHubAccess) async throws -> FiledIssue {
        var create = request("POST", api.appending(path: "repos/\(destination.slug)/issues"), token: access.token)
        create.setValue("application/json", forHTTPHeaderField: "Content-Type")
        create.httpBody = try JSONSerialization.data(withJSONObject: [
            "title": issue.title, "body": issue.body, "labels": issue.labels,
        ])
        let body = try await json(create)
        guard let number = body["number"] as? Int, let text = body["html_url"] as? String, let url = URL(string: text) else {
            throw FeedbackFilingError.unexpectedResponse
        }
        return FiledIssue(number: number, url: url)
    }

    // MARK: - HTTP

    private func request(_ method: String, _ url: URL, token: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.timeoutInterval = 30
        return request
    }

    /// Sends a request and decodes a JSON object, mapping failures to ``FeedbackFilingError``.
    private func json(_ request: URLRequest, onRepository: Bool = false) async throws -> [String: Any] {
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch let error as FeedbackFilingError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw FeedbackFilingError.network
        }
        guard (200..<300).contains(response.statusCode) else {
            throw FeedbackFilingError.forStatus(
                response.statusCode,
                rateLimitRemaining: response.value(forHTTPHeaderField: "x-ratelimit-remaining"),
                onRepository: onRepository
            )
        }
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw FeedbackFilingError.unexpectedResponse
        }
        return object
    }
}
