import Foundation
@testable import HassCore
import Testing

/// Files one real report through GitHub, only when `FENTON_LIVE_GITHUB_TOKEN` is set (never in CI). The
/// issue carries `On Hold` so the triage agent skips it; close it afterwards.
@Suite("GitHub feedback live check", .enabled(if: ProcessInfo.processInfo.environment["FENTON_LIVE_GITHUB_TOKEN"] != nil))
struct GitHubFeedbackLiveTests {
    @Test func filesAReportWithAPhoto() async throws {
        let token = try #require(ProcessInfo.processInfo.environment["FENTON_LIVE_GITHUB_TOKEN"])
        let client = GitHubFeedbackClient()
        let access = try await client.verify(token: token)
        let folder = try FeedbackMediaFixture.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = try FeedbackMediaFixture.image(in: folder, name: "live-check.png", type: .png, gps: false)
        let attachment = FeedbackAttachment(fileURL: image, filename: "live-check.png", mimeType: "image/png",
                                            byteCount: try FeedbackMediaFitter.byteCount(image), isVideo: false)
        let url = try await client.upload(attachment, access: access)
        var draft = FeedbackDraft(kind: .bug)
        draft.setTitle("[Bug] Live filing check (ignore)")
        draft.description = "Filed by GitHubFeedbackLiveTests to check the GitHub path. Safe to close."
        let diagnostics = FeedbackDiagnostics(app: "test", system: "macOS", device: "Mac (test host)", window: "n/a",
                                              homeAssistant: "Not connected", reporter: nil, accessibility: "n/a", locale: "n/a")
        var issue = FeedbackIssue.compose(draft: draft, platform: .ios, diagnostics: diagnostics, media: [(attachment, url)])
        issue.labels.append("On Hold")
        let filed = try await client.createIssue(issue, access: access)
        #expect(filed.number > 0)
        print("LIVE_ISSUE \(filed.url.absoluteString)")
    }
}
