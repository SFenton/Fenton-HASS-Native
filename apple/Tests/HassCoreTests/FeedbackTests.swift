import Foundation
@testable import HassCore
import Testing

// MARK: - Draft

@Suite("Feedback draft")
struct FeedbackDraftTests {
    @Test func prefixIsKept() {
        var draft = FeedbackDraft(kind: .bug)
        #expect(draft.title == "[Bug] ")
        draft.setTitle("[Bug] Lights flicker")
        #expect(draft.title == "[Bug] Lights flicker")
        draft.setTitle("[Bug]")
        #expect(draft.title == "[Bug] ")
        draft.setTitle("[Bu")
        #expect(draft.title == "[Bug] ")
        draft.setTitle("Typed over")
        #expect(draft.title == "[Bug] Typed over")
        draft.setTitle("[Bug]Squashed")
        #expect(draft.title == "[Bug] Squashed")
        #expect(FeedbackDraft.prefixedTitle("   spaced", kind: .feature) == "[Feature] spaced")
    }

    @Test func validationOrder() {
        var draft = FeedbackDraft(kind: .bug)
        #expect(draft.validationIssue == .missingTitle)
        #expect(!draft.hasTypedInput)
        draft.setTitle("[Bug] X")
        #expect(draft.hasTypedInput)
        #expect(draft.validationIssue == .missingDescription)
        draft.description = "  "
        #expect(draft.validationIssue == .missingDescription)
        draft.description = "Broken"
        #expect(draft.validationIssue == nil)
        draft.reproSteps = String(repeating: "a", count: FeedbackLimits.bodyCharacters + 1)
        #expect(draft.validationIssue == .textTooLong)
        draft.reproSteps = ""
        draft.setTitle("[Bug] " + String(repeating: "t", count: FeedbackLimits.titleCharacters))
        #expect(draft.validationIssue == .titleTooLong)
    }

    @Test func featureIgnoresReproBoxes() {
        var draft = FeedbackDraft(kind: .feature)
        draft.setTitle("[Feature] Idea")
        draft.description = "More"
        draft.reproSteps = String(repeating: "a", count: FeedbackLimits.bodyCharacters + 1)
        #expect(draft.validationIssue == nil)
        #expect(!FeedbackDraft(kind: .feature).hasTypedInput)
        var expected = FeedbackDraft(kind: .bug)
        expected.expectedBehavior = "x"
        #expect(expected.hasTypedInput)
    }

    @Test func messagesAndKindCopy() {
        for issue in [FeedbackValidationIssue.missingTitle, .titleTooLong, .missingDescription, .textTooLong] {
            #expect(!issue.message.isEmpty)
        }
        #expect(FeedbackKind.bug.formTitle == "Report an Issue")
        #expect(FeedbackKind.feature.formTitle == "Request a Feature")
        #expect(FeedbackKind.bug.label == "Bug" && FeedbackKind.feature.label == "Feature")
        #expect(FeedbackKind.bug.noun == "report" && FeedbackKind.feature.noun == "request")
        #expect(FeedbackKind.bug.symbol == "ladybug" && FeedbackKind.feature.symbol == "lightbulb")
        #expect(FeedbackKind.bug.includesReproduction && !FeedbackKind.feature.includesReproduction)
        #expect(FeedbackKind.allCases.allSatisfy { !$0.rowSubtitle.isEmpty && $0.id == $0.rawValue })
    }
}

// MARK: - Platform, attachments

@Suite("Feedback platform and attachments")
struct FeedbackAttachmentTests {
    @Test func platformPrecedence() {
        #expect(FeedbackPlatform.resolve(isPad: false, hasHinge: false) == .ios)
        #expect(FeedbackPlatform.resolve(isPad: true, hasHinge: false) == .ipados)
        #expect(FeedbackPlatform.resolve(isPad: false, hasHinge: true) == .iphoneDuo)
        #expect(FeedbackPlatform.resolve(isPad: true, hasHinge: true) == .iphoneDuo)
        #expect(FeedbackPlatform.allCases.map(\.label) == ["iOS", "iPadOS", "iPhone Duo"])
    }

    @Test func mediaClassification() {
        #expect(FeedbackAttachmentPolicy.media(forFilename: "a.png")?.isVideo == false)
        #expect(FeedbackAttachmentPolicy.media(forFilename: "a.PNG")?.mimeType == "image/png")
        #expect(FeedbackAttachmentPolicy.media(forFilename: "clip.mov")?.isVideo == true)
        #expect(FeedbackAttachmentPolicy.media(forFilename: "clip.mp4")?.mimeType == "video/mp4")
        #expect(FeedbackAttachmentPolicy.media(forFilename: "notes.txt") == nil)
        #expect(FeedbackAttachmentPolicy.media(forFilename: "noext") == nil)
    }

    @Test func filenamesAreSanitized() {
        #expect(FeedbackAttachmentPolicy.sanitizedFilename("dir/IMG 1.png") == "IMG 1.png")
        #expect(FeedbackAttachmentPolicy.sanitizedFilename("a\"b:c[d](e)<f>.jpg") == "abcdef.jpg")
        #expect(FeedbackAttachmentPolicy.sanitizedFilename("  \n ") == "attachment")
        let long = FeedbackAttachmentPolicy.sanitizedFilename(String(repeating: "x", count: 200) + ".mov")
        #expect(long.count == 120 && long.hasSuffix(".mov"))
        #expect(FeedbackAttachmentPolicy.sanitizedFilename(String(repeating: "y", count: 130)).count == 120)
    }

    @Test func admissionLimits() {
        let one = attachment()
        #expect(FeedbackAttachmentPolicy.rejection(byteCount: 10, filename: "a", existing: []) == nil)
        #expect(FeedbackAttachmentPolicy.rejection(byteCount: FeedbackLimits.attachmentBytes + 1, filename: "a", existing: []) == .fileTooLarge("a"))
        let full = Array(repeating: one, count: FeedbackLimits.attachments)
        #expect(FeedbackAttachmentPolicy.rejection(byteCount: 1, filename: "a", existing: full) == .tooMany)
        for rejection in [FeedbackAttachmentRejection.tooMany, .fileTooLarge("a"), .unsupportedType("a"), .unreadable, .locationNotRemoved("a")] {
            #expect(rejection.errorDescription?.isEmpty == false)
        }
    }

    @Test func accessibilityLabel() {
        let photo = attachment(name: "shot.png", bytes: 2_000_000, video: false)
        #expect(photo.accessibilityLabel(position: 1).hasPrefix("Photo 1, shot.png, "))
        #expect(attachment(name: "clip.mov", video: true).accessibilityLabel(position: 2).hasPrefix("Video 2, clip.mov"))
    }

    func attachment(name: String = "a.png", bytes: Int64 = 10, video: Bool = false) -> FeedbackAttachment {
        FeedbackAttachment(fileURL: URL(fileURLWithPath: "/tmp/\(name)"), filename: name,
                           mimeType: video ? "video/quicktime" : "image/png", byteCount: bytes, isVideo: video)
    }
}

// MARK: - Issue

@Suite("Feedback issue composition")
struct FeedbackIssueTests {
    static let diagnostics = FeedbackDiagnostics(
        app: "0.1.0 (1)", system: "iOS 27.1", device: "iPhone (iPhone18,1)", window: "402 × 874 pt, compact width, portrait",
        homeAssistant: "2026.10.1, connected", reporter: "Stephen", accessibility: "Text large, VoiceOver off, Reduce Motion off, Light",
        locale: "en_US, America/Los_Angeles"
    )

    @Test func bugIssue() throws {
        var draft = FeedbackDraft(kind: .bug)
        draft.setTitle("[Bug] Garage\nstuck")
        draft.description = "It <!-- hides --> things"
        draft.reproSteps = "1. Open\n2. Tap"
        draft.expectedBehavior = " "
        let photo = FeedbackAttachment(fileURL: URL(fileURLWithPath: "/tmp/a.png"), filename: "a.png", mimeType: "image/png", byteCount: 1, isVideo: false)
        let video = FeedbackAttachment(fileURL: URL(fileURLWithPath: "/tmp/b.mov"), filename: "b.mov", mimeType: "video/quicktime", byteCount: 1, isVideo: true)
        let issue = FeedbackIssue.compose(draft: draft, platform: .iphoneDuo, diagnostics: Self.diagnostics, media: [
            (photo, URL(string: "https://github.com/user-attachments/assets/1")!),
            (video, URL(string: "https://github.com/user-attachments/assets/2")!),
        ])
        #expect(issue.title == "[Bug] Garage stuck")
        #expect(issue.labels == ["Bug", "From App", "iPhone Duo"])
        #expect(issue.body.contains("### Description\n\nIt &lt;!-- hides --> things"))
        #expect(issue.body.contains("### Steps to Reproduce\n\n1. Open\n2. Tap"))
        #expect(!issue.body.contains("Expected Behavior"))
        #expect(issue.body.contains("![a.png](https://github.com/user-attachments/assets/1)\n\nhttps://github.com/user-attachments/assets/2"))
        #expect(issue.body.contains("| Reported by | Stephen |"))
        #expect(issue.body.contains("| Home Assistant | 2026.10.1, connected |"))
        #expect(issue.body.hasSuffix(FeedbackIssue.marker))
        #expect(issue.body.components(separatedBy: FeedbackIssue.marker).count == 2)
    }

    @Test func featureIssueWithoutMedia() {
        var draft = FeedbackDraft(kind: .feature)
        draft.setTitle("[Feature] Dark mode")
        draft.description = "Please"
        draft.reproSteps = "ignored"
        var diagnostics = Self.diagnostics
        diagnostics.reporter = nil
        diagnostics.locale = "a|b"
        let issue = FeedbackIssue.compose(draft: draft, platform: .ios, diagnostics: diagnostics, media: [])
        #expect(issue.labels == ["Feature", "From App", "iOS"])
        #expect(!issue.body.contains("### Media"))
        #expect(!issue.body.contains("Steps to Reproduce"))
        #expect(!issue.body.contains("Reported by"))
        #expect(issue.body.contains("| Locale | a\\|b |"))
    }

    @Test func diagnosticsFormatting() {
        #expect(FeedbackDiagnostics.appVersion(["CFBundleShortVersionString": "1.2", "CFBundleVersion": "7"]) == "1.2 (7)")
        #expect(FeedbackDiagnostics.appVersion(nil) == "? (?)")
        let date = Date(timeIntervalSince1970: 1_791_900_000)
        #expect(FeedbackDiagnostics.appVersion(["CFBundleShortVersionString": "1", "CFBundleVersion": "2"], buildDate: date).hasPrefix("1 (2), built 2026-"))
        #expect(FeedbackDiagnostics.windowText(width: 402, height: 874.4, regularWidth: false) == "402 × 874 pt, compact width, portrait")
        #expect(FeedbackDiagnostics.windowText(width: 1210, height: 834, regularWidth: true) == "1210 × 834 pt, regular width, landscape")
        #expect(Self.diagnostics.rows.map(\.label) == ["App", "System", "Device", "Window", "Home Assistant", "Reported by", "Accessibility", "Locale"])
    }

    @Test func destination() throws {
        let destination = FeedbackDestination.requests
        #expect(destination.slug == "SFenton/fenton-hass-requests")
        let url = destination.tokenCreationURL.absoluteString
        #expect(url.hasPrefix("https://github.com/settings/personal-access-tokens/new?"))
        #expect(url.contains("issues=write") && url.contains("target_name=SFenton"))
        #expect(FiledIssue(number: 3, url: URL(string: "https://x")!).number == 3)
    }
}

// MARK: - GitHub client

/// Records requests and answers from a script.
final class StubFeedbackTransport: FeedbackHTTPTransport, @unchecked Sendable {
    typealias Reply = (status: Int, body: String, headers: [String: String])
    private let lock = NSLock()
    private var replies: [Reply]
    private(set) var requests: [URLRequest] = []
    var error: (any Error)?

    init(_ replies: [Reply]) { self.replies = replies }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let reply: Reply = try lock.withLock {
            requests.append(request)
            if let error { throw error }
            return replies.isEmpty ? (500, "{}", [:]) : replies.removeFirst()
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: reply.headers)!
        return (Data(reply.body.utf8), response)
    }
}

@Suite("GitHub feedback client")
struct GitHubFeedbackClientTests {
    let access = GitHubAccess(token: "t0ken", login: "SFenton", repositoryID: 42)

    @Test func verifyReadsUserAndRepository() async throws {
        let transport = StubFeedbackTransport([(200, #"{"login":"SFenton"}"#, [:]), (200, #"{"id":42}"#, [:])])
        let access = try await GitHubFeedbackClient(transport: transport).verify(token: "  t0ken\n")
        #expect(access == GitHubAccess(token: "t0ken", login: "SFenton", repositoryID: 42))
        #expect(transport.requests.map { $0.url!.path } == ["/user", "/repos/SFenton/fenton-hass-requests"])
        #expect(transport.requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer t0ken")
        #expect(transport.requests[0].value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2022-11-28")
    }

    @Test func verifyMapsFailures() async {
        await #expect(throws: FeedbackFilingError.tokenRejected) {
            try await GitHubFeedbackClient(transport: StubFeedbackTransport([(401, "{}", [:])])).verify(token: "x")
        }
        await #expect(throws: FeedbackFilingError.noRepositoryAccess) {
            try await GitHubFeedbackClient(transport: StubFeedbackTransport([(200, #"{"login":"a"}"#, [:]), (404, "{}", [:])])).verify(token: "x")
        }
        await #expect(throws: FeedbackFilingError.unexpectedResponse) {
            try await GitHubFeedbackClient(transport: StubFeedbackTransport([(200, #"{"login":"a"}"#, [:]), (200, #"[]"#, [:])])).verify(token: "x")
        }
        await #expect(throws: FeedbackFilingError.unexpectedResponse) {
            try await GitHubFeedbackClient(transport: StubFeedbackTransport([(200, #"{"x":1}"#, [:]), (200, #"{"id":1}"#, [:])])).verify(token: "x")
        }
        let offline = StubFeedbackTransport([])
        offline.error = URLError(.notConnectedToInternet)
        await #expect(throws: FeedbackFilingError.network) { try await GitHubFeedbackClient(transport: offline).verify(token: "x") }
        let cancelled = StubFeedbackTransport([])
        cancelled.error = CancellationError()
        await #expect(throws: CancellationError.self) { try await GitHubFeedbackClient(transport: cancelled).verify(token: "x") }
        let typed = StubFeedbackTransport([])
        typed.error = FeedbackFilingError.rateLimited
        await #expect(throws: FeedbackFilingError.rateLimited) { try await GitHubFeedbackClient(transport: typed).verify(token: "x") }
    }

    @Test func uploadSendsTheFileToUserAttachments() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("upload-\(UUID().uuidString).png")
        try Data([1, 2, 3]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let attachment = FeedbackAttachment(fileURL: file, filename: "shot one.png", mimeType: "image/png", byteCount: 3, isVideo: false)
        let transport = StubFeedbackTransport([(201, #"{"url":"https://github.com/user-attachments/assets/abc"}"#, [:])])
        let url = try await GitHubFeedbackClient(transport: transport).upload(attachment, access: access)
        #expect(url.absoluteString == "https://github.com/user-attachments/assets/abc")
        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.host() == "uploads.github.com")
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(query.contains(URLQueryItem(name: "repository_id", value: "42")))
        #expect(query.contains(URLQueryItem(name: "name", value: "shot one.png")))
        #expect(query.contains(URLQueryItem(name: "content_type", value: "image/png")))
        #expect(request.httpBody == Data([1, 2, 3]))
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/octet-stream")
    }

    @Test func uploadFailures() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("upload-\(UUID().uuidString).png")
        try Data([1]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let attachment = FeedbackAttachment(fileURL: file, filename: "a.png", mimeType: "image/png", byteCount: 1, isVideo: false)
        await #expect(throws: FeedbackFilingError.attachmentRejected("a.png")) {
            try await GitHubFeedbackClient(transport: StubFeedbackTransport([(422, "{}", [:])])).upload(attachment, access: access)
        }
        await #expect(throws: FeedbackFilingError.unexpectedResponse) {
            try await GitHubFeedbackClient(transport: StubFeedbackTransport([(201, #"{"url":"http://insecure"}"#, [:])])).upload(attachment, access: access)
        }
        let missing = FeedbackAttachment(fileURL: URL(fileURLWithPath: "/nonexistent/x.png"), filename: "x.png", mimeType: "image/png", byteCount: 1, isVideo: false)
        await #expect(throws: FeedbackFilingError.attachmentRejected("x.png")) {
            try await GitHubFeedbackClient(transport: StubFeedbackTransport([])).upload(missing, access: access)
        }
        await #expect(throws: FeedbackFilingError.tokenRejected) {
            try await GitHubFeedbackClient(transport: StubFeedbackTransport([(401, "{}", [:])])).upload(attachment, access: access)
        }
    }

    @Test func createIssuePostsTitleBodyAndLabels() async throws {
        let transport = StubFeedbackTransport([(201, #"{"number":7,"html_url":"https://github.com/SFenton/fenton-hass-requests/issues/7"}"#, [:])])
        let issue = FeedbackIssue(title: "[Bug] X", body: "Body", labels: ["Bug", "From App", "iOS"])
        let filed = try await GitHubFeedbackClient(transport: transport).createIssue(issue, access: access)
        #expect(filed.number == 7)
        let request = try #require(transport.requests.first)
        #expect(request.url?.path == "/repos/SFenton/fenton-hass-requests/issues")
        let json = try #require(try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        #expect(json["title"] as? String == "[Bug] X")
        #expect(json["labels"] as? [String] == ["Bug", "From App", "iOS"])
        await #expect(throws: FeedbackFilingError.unexpectedResponse) {
            try await GitHubFeedbackClient(transport: StubFeedbackTransport([(201, #"{"number":7}"#, [:])])).createIssue(issue, access: access)
        }
        await #expect(throws: FeedbackFilingError.noIssueAccess) {
            try await GitHubFeedbackClient(transport: StubFeedbackTransport([(403, "{}", [:])])).createIssue(issue, access: access)
        }
    }

    @Test func statusMapping() {
        #expect(FeedbackFilingError.forStatus(401, rateLimitRemaining: nil) == .tokenRejected)
        #expect(FeedbackFilingError.forStatus(403, rateLimitRemaining: "0") == .rateLimited)
        #expect(FeedbackFilingError.forStatus(429, rateLimitRemaining: nil) == .rateLimited)
        #expect(FeedbackFilingError.forStatus(403, rateLimitRemaining: "10") == .noIssueAccess)
        #expect(FeedbackFilingError.forStatus(404, rateLimitRemaining: nil, onRepository: true) == .noRepositoryAccess)
        #expect(FeedbackFilingError.forStatus(502, rateLimitRemaining: nil) == .unavailable)
        #expect(FeedbackFilingError.forStatus(418, rateLimitRemaining: nil) == .httpStatus(418))
        let all: [FeedbackFilingError] = [.tokenRejected, .noRepositoryAccess, .noIssueAccess, .attachmentRejected("a"), .rateLimited,
                                          .unavailable, .httpStatus(1), .network, .unexpectedResponse]
        #expect(all.allSatisfy { $0.errorDescription?.isEmpty == false })
        #expect(all.filter(\.needsNewToken) == [.tokenRejected, .noRepositoryAccess, .noIssueAccess])
    }
}

// MARK: - Fixture and stores

@Suite("Feedback fixture and token stores")
struct FeedbackFixtureTests {
    @Test func fixtureAnswers() async throws {
        let fixture = FeedbackFixtureFiler()
        #expect(try await fixture.verify(token: " fixture-token ") == FeedbackFixtureFiler.access)
        await #expect(throws: FeedbackFilingError.tokenRejected) { try await fixture.verify(token: "nope") }
        let attachment = FeedbackAttachment(fileURL: URL(fileURLWithPath: "/tmp/a.png"), filename: "a.png", mimeType: "image/png", byteCount: 1, isVideo: false)
        #expect(try await fixture.upload(attachment, access: FeedbackFixtureFiler.access).absoluteString.hasSuffix("fixture-1"))
        let filed = try await fixture.createIssue(FeedbackIssue(title: "[Bug] ok", body: "", labels: []), access: FeedbackFixtureFiler.access)
        #expect(filed.number == 1)
        #expect(fixture.createdIssues.count == 1)
        await #expect(throws: FeedbackFilingError.unavailable) {
            try await fixture.createIssue(FeedbackIssue(title: "fixture-failed", body: "", labels: []), access: FeedbackFixtureFiler.access)
        }
        await #expect(throws: FeedbackFilingError.tokenRejected) {
            try await fixture.createIssue(FeedbackIssue(title: "fixture-token", body: "", labels: []), access: FeedbackFixtureFiler.access)
        }
    }

    @Test func inMemoryStore() throws {
        let store = InMemoryGitHubAccessStore()
        #expect(store.load() == nil)
        try store.save(FeedbackFixtureFiler.access)
        #expect(store.load() == FeedbackFixtureFiler.access)
        store.clear()
        #expect(store.load() == nil)
    }

    @Test func keychainStoreRoundTripsWhenTheKeychainIsAvailable() throws {
        let store = KeychainGitHubAccessStore(service: "com.sfenton.home.github.tests.\(UUID().uuidString)")
        defer { store.clear() }
        // Hosted macOS test runs may lack a keychain entitlement for synchronizable items; only check
        // the round trip when saving works.
        guard (try? store.save(FeedbackFixtureFiler.access)) != nil else { return }
        #expect(store.load() == FeedbackFixtureFiler.access)
        store.clear()
        #expect(store.load() == nil)
    }
}
