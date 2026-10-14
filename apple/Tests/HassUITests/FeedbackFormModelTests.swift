import Foundation
@testable import HassCore
@testable import HassUI
import SwiftUI
import Testing

/// A filer whose answers a test scripts.
final class ScriptedFiler: FeedbackFiling, @unchecked Sendable {
    var uploadError: FeedbackFilingError?
    var createError: (any Error)?
    var uploadDelay: Duration = .zero
    private(set) var uploads: [String] = []
    private(set) var issues: [FeedbackIssue] = []

    func verify(token: String) async throws -> GitHubAccess {
        guard token == "good" else { throw FeedbackFilingError.tokenRejected }
        return GitHubAccess(token: token, login: "octo", repositoryID: 9)
    }

    func upload(_ attachment: FeedbackAttachment, access: GitHubAccess) async throws -> URL {
        try await Task.sleep(for: uploadDelay)
        if let uploadError { throw uploadError }
        uploads.append(attachment.filename)
        return URL(string: "https://github.com/user-attachments/assets/\(uploads.count)")!
    }

    func createIssue(_ issue: FeedbackIssue, access: GitHubAccess) async throws -> FiledIssue {
        if let createError { throw createError }
        issues.append(issue)
        return FiledIssue(number: 12, url: URL(string: "https://github.com/SFenton/fenton-hass-requests/issues/12")!)
    }
}

@MainActor
@Suite("Feedback form model", .serialized)
struct FeedbackFormModelTests {
    static let access = GitHubAccess(token: "good", login: "octo", repositoryID: 9)
    static let diagnostics = FeedbackDiagnostics(app: "1 (1)", system: "iOS 27", device: "iPhone (x)", window: "w",
                                                 homeAssistant: "Connected", reporter: nil, accessibility: "a", locale: "l")

    func model(_ filer: ScriptedFiler = ScriptedFiler(), access: GitHubAccess? = access, kind: FeedbackKind = .bug) -> FeedbackFormModel {
        FeedbackFormModel(kind: kind, services: FeedbackServices(filer: filer, store: InMemoryGitHubAccessStore(access)))
    }

    func fill(_ model: FeedbackFormModel) {
        model.title = "[Bug] Lights"
        model.descriptionText = "Flicker"
        model.reproSteps = "Open Home"
        model.expectedBehavior = "Steady"
    }

    /// Waits until the model leaves `.sending`.
    func settle(_ model: FeedbackFormModel) async {
        for _ in 0..<200 where model.isSending { try? await Task.sleep(for: .milliseconds(10)) }
    }

    func stagedImage(_ name: String = "shot.png") throws -> URL {
        let folder = FeedbackPickedMedia.stagingFolder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try FeedbackUITestMedia.image(in: folder, name: name, type: .png, gps: true)
    }

    @Test func draftBindingsAndBlockingReasons() {
        let model = model(access: nil)
        #expect(model.title == "[Bug] ")
        #expect(model.blockingReason == FeedbackValidationIssue.missingTitle.message)
        #expect(!model.hasUnsavedInput)
        fill(model)
        #expect(model.reproSteps == "Open Home" && model.expectedBehavior == "Steady" && model.descriptionText == "Flicker")
        #expect(model.hasUnsavedInput)
        #expect(model.blockingReason == "Add a GitHub access token to send.")
        #expect(!model.canSubmit)
        let connected = self.model()
        fill(connected)
        #expect(connected.blockingReason == nil && connected.canSubmit)
    }

    @Test func submitUploadsMediaThenFiles() async throws {
        let filer = ScriptedFiler()
        let model = model(filer)
        fill(model)
        await model.admit(try stagedImage(), displayName: "shot.png")
        #expect(model.attachments.count == 1)
        #expect(try !FeedbackLocationScrubber.imageHasLocation(model.attachments[0].fileURL))
        model.submit(platform: .ipados) { Self.diagnostics }
        #expect(model.isSending)
        await settle(model)
        #expect(model.phase == .finished(FiledIssue(number: 12, url: URL(string: "https://github.com/SFenton/fenton-hass-requests/issues/12")!)))
        #expect(filer.uploads == ["shot.png"])
        let issue = try #require(filer.issues.first)
        #expect(issue.labels == ["Bug", "From App", "iPadOS"])
        #expect(issue.body.contains("![shot.png](https://github.com/user-attachments/assets/1)"))
        model.discardMedia()
        #expect(model.attachments.isEmpty)
    }

    @Test func failuresKeepTheFormAndFlagTokenProblems() async {
        let filer = ScriptedFiler()
        filer.createError = FeedbackFilingError.tokenRejected
        let model = model(filer)
        fill(model)
        model.submit(platform: .ios) { Self.diagnostics }
        await settle(model)
        #expect(model.phase == .failed(FeedbackFilingError.tokenRejected.errorDescription!, needsToken: true))
        model.acknowledgeFailure()
        #expect(model.phase == .editing)
        #expect(model.title == "[Bug] Lights")
        filer.createError = URLError(.timedOut)
        model.submit(platform: .ios) { Self.diagnostics }
        await settle(model)
        #expect(model.phase == .failed(FeedbackFilingError.network.errorDescription!, needsToken: false))
    }

    @Test func stopSendingReturnsToEditing() async throws {
        let filer = ScriptedFiler()
        filer.uploadDelay = .seconds(5)
        let model = model(filer)
        fill(model)
        await model.admit(try stagedImage(), displayName: "shot.png")
        model.submit(platform: .ios) { Self.diagnostics }
        #expect(model.phase == .sending(step: 1, total: 2))
        model.cancelSubmit()
        #expect(model.phase == .editing)
        await settle(model)
        #expect(filer.issues.isEmpty)
        model.cancelSubmit()
        model.discardMedia()
    }

    @Test func refusals() async throws {
        let model = model()
        let text = FeedbackPickedMedia.stagingFolder.appendingPathComponent("notes-\(UUID()).txt")
        try FileManager.default.createDirectory(at: FeedbackPickedMedia.stagingFolder, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: text)
        await model.admit(text, displayName: "notes.txt")
        #expect(model.attachmentMessage == FeedbackAttachmentRejection.unsupportedType("notes.txt").errorDescription)
        #expect(!FileManager.default.fileExists(atPath: text.path))
        let broken = FeedbackPickedMedia.stagingFolder.appendingPathComponent("broken-\(UUID()).png")
        try Data(repeating: 1, count: 8).write(to: broken)
        await model.admit(broken, displayName: "broken.png")
        #expect(model.attachmentMessage == FeedbackAttachmentRejection.unreadable.errorDescription)
        for index in 0..<FeedbackLimits.attachments { await model.admit(try stagedImage("p\(index).png"), displayName: "p\(index).png") }
        #expect(model.attachments.count == FeedbackLimits.attachments)
        await model.admit(try stagedImage("extra.png"), displayName: "extra.png")
        #expect(model.attachmentMessage == FeedbackAttachmentRejection.tooMany.errorDescription)
        model.remove(model.attachments[0])
        #expect(model.attachments.count == FeedbackLimits.attachments - 1 && model.attachmentMessage == nil)
        await model.importFiles(.failure(URLError(.cancelled)))
        #expect(model.attachmentMessage == FeedbackAttachmentRejection.unreadable.errorDescription)
        model.discardMedia()
        FeedbackFormModel.purgeStagedMedia()
        #expect(!FileManager.default.fileExists(atPath: FeedbackPickedMedia.stagingFolder.path))
    }

    @Test func importFilesStagesACopy() async throws {
        let folder = try FeedbackUITestMedia.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = try FeedbackUITestMedia.image(in: folder, name: "picked.jpg", type: .jpeg, gps: true)
        let model = model()
        await model.importFiles(.success([original]))
        #expect(model.attachments.count == 1)
        #expect(model.attachments[0].fileURL.path.hasPrefix(FeedbackPickedMedia.stagingFolder.path))
        #expect(try FeedbackLocationScrubber.imageHasLocation(original), "The original keeps its metadata")
        await model.importFiles(.success([folder.appendingPathComponent("missing.jpg")]))
        #expect(model.attachmentMessage == FeedbackAttachmentRejection.unreadable.errorDescription)
        model.discardMedia()
    }

    @Test func accessModelVerifiesBeforeSaving() async {
        let store = InMemoryGitHubAccessStore()
        let services = FeedbackServices(filer: ScriptedFiler(), store: store)
        let access = GitHubAccessModel(services: services)
        #expect(access.access == nil && !access.canSave)
        access.tokenText = "bad"
        #expect(await access.save() == false)
        #expect(access.check == .failed(FeedbackFilingError.tokenRejected.errorDescription!))
        #expect(store.load() == nil)
        access.tokenText = "good"
        #expect(await access.save())
        #expect(access.tokenText.isEmpty && access.access?.login == "octo" && store.load()?.login == "octo")
        let form = FeedbackFormModel(kind: .feature, services: services)
        #expect(form.access?.login == "octo")
        access.remove()
        #expect(store.load() == nil && access.access == nil)
        await form.refreshAccess()
        #expect(form.access == nil)
    }

    @Test func servicesResolveFromTheEnvironment() {
        #expect(FeedbackServices.resolve(["FENTON_FEEDBACK_FIXTURE": "1"]).store.load() == FeedbackFixtureFiler.access)
        #expect(FeedbackServices.resolve(["FENTON_FEEDBACK_FIXTURE": "connect"]).store.load() == nil)
        #expect(FeedbackServices.resolve([:]).filer is GitHubFeedbackClient)
    }

    @Test func diagnosticsCollector() {
        let traits = FeedbackDiagnosticsCollector.Traits(dynamicTypeSize: .xLarge, colorScheme: .dark, regularWidth: true,
                                                         voiceOver: true, reduceMotion: false)
        let diagnostics = FeedbackDiagnosticsCollector.diagnostics(platform: .iphoneDuo, traits: traits,
                                                                   homeAssistant: "2026.10.1, connected", reporter: "Stephen")
        #expect(diagnostics.device.hasPrefix("iPhone Duo ("))
        #expect(diagnostics.accessibility == "Text xLarge, VoiceOver on, Reduce Motion off, Dark")
        #expect(diagnostics.reporter == "Stephen")
        #expect(diagnostics.window.contains("regular width"))
        #expect(!diagnostics.system.isEmpty && !diagnostics.app.isEmpty)
        #expect(FeedbackDiagnosticsCollector.familyName(.ios) == "iPhone" && FeedbackDiagnosticsCollector.familyName(.ipados) == "iPad")
    }

    /// Hosted renders of the Settings section, both forms (with and without a token) and the GitHub page.
    @Test func hostedRenders() {
        let session = AppSession(tokenStore: InMemoryTokenStore(), snapshotCache: EntitySnapshotCache(
            fileURL: FileManager.default.temporaryDirectory.appending(path: "feedback-\(UUID()).json")))
        let store = EntityStore()
        let connection = HassConnection(server: .fentonHome, tokens: TokenManager(store: InMemoryTokenStore()), store: store)
        let connected = FeedbackServices(filer: ScriptedFiler(), store: InMemoryGitHubAccessStore(Self.access))
        let missing = FeedbackServices(filer: ScriptedFiler(), store: InMemoryGitHubAccessStore())
        let views: [AnyView] = [
            AnyView(NavigationStack { List { FeedbackSettingsSection(openForm: .constant(nil)) } }),
            AnyView(FeedbackFormSheet(kind: .bug, services: connected)),
            AnyView(FeedbackFormSheet(kind: .feature, services: missing)),
            AnyView(NavigationStack { GitHubAccessView(services: connected) }),
            AnyView(NavigationStack { GitHubAccessView(services: missing) }),
            AnyView(FeedbackFieldHeader("Title", detail: "Detail")),
        ]
        for view in views {
            let hosted = view.environment(session).environment(connection).environment(store).frame(width: 402, height: 874)
            #expect(ImageRenderer(content: hosted).cgImage != nil)
        }
    }

    @Test func settingsListHostsTheSection() {
        let host = SheetHostWindow(FeedbackSettingsSection(openForm: .constant(.bug)).feedbackFormSheet(item: .constant(nil)))
        host.settle()
        #expect(!host.hasSheet)
    }
}
