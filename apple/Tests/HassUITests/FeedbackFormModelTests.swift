import Foundation
@testable import HassCore
@testable import HassUI
import SwiftUI
import Testing

/// A filer whose answers a test scripts.
final class ScriptedFiler: FeedbackFiling, @unchecked Sendable {
    var available: Result<Bool, any Error> = .success(true)
    var uploadError: FeedbackFilingError?
    var submitError: (any Error)?
    var uploadDelay: Duration = .zero
    private(set) var uploads: [String] = []
    private(set) var reports: [FeedbackReport] = []

    func isAvailable() async throws -> Bool { try available.get() }

    func upload(_ attachment: FeedbackAttachment) async throws -> URL {
        try await Task.sleep(for: uploadDelay)
        if let uploadError { throw uploadError }
        uploads.append(attachment.filename)
        return URL(string: "https://github.com/user-attachments/assets/\(uploads.count)")!
    }

    func submit(_ report: FeedbackReport) async throws -> FiledIssue {
        if let submitError { throw submitError }
        reports.append(report)
        return FiledIssue(number: 12, url: URL(string: "https://github.com/SFenton/fenton-hass-requests/issues/12")!)
    }
}

@MainActor
@Suite("Feedback form model", .serialized)
struct FeedbackFormModelTests {
    static let diagnostics = FeedbackDiagnostics(app: "1 (1)", system: "iOS 27", device: "iPhone (x)", window: "w",
                                                 homeAssistant: "Connected", accessibility: "a", locale: "l")

    /// A model whose availability check has run.
    func model(_ filer: ScriptedFiler = ScriptedFiler(), kind: FeedbackKind = .bug) async -> FeedbackFormModel {
        let model = FeedbackFormModel(kind: kind, services: FeedbackServices(filer: filer))
        await model.checkAvailability()
        return model
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

    @Test func draftBindingsAndBlockingReasons() async {
        let unavailable = ScriptedFiler()
        unavailable.available = .success(false)
        let model = await model(unavailable)
        #expect(model.title == "[Bug] ")
        #expect(model.blockingReason == FeedbackValidationIssue.missingTitle.message)
        #expect(!model.hasUnsavedInput)
        fill(model)
        #expect(model.reproSteps == "Open Home" && model.expectedBehavior == "Steady" && model.descriptionText == "Flicker")
        #expect(model.hasUnsavedInput)
        #expect(model.availability == .unavailable)
        #expect(model.blockingReason == "Reporting isn't set up in Home Assistant yet.")
        #expect(!model.canSubmit)
        let checking = FeedbackFormModel(kind: .bug, services: FeedbackServices(filer: ScriptedFiler()))
        fill(checking)
        #expect(checking.blockingReason == "Checking Home Assistant…")
        let failing = ScriptedFiler()
        failing.available = .failure(URLError(.timedOut))
        let unknown = await self.model(failing)
        fill(unknown)
        #expect(unknown.availability == .available, "A failed check lets Submit show the real error")
        let connected = await self.model()
        fill(connected)
        #expect(connected.blockingReason == nil && connected.canSubmit)
    }

    @Test func submitUploadsMediaThenFiles() async throws {
        let filer = ScriptedFiler()
        let model = await model(filer)
        fill(model)
        await model.admit(try stagedImage(), displayName: "shot.png")
        #expect(model.attachments.count == 1)
        #expect(try !FeedbackLocationScrubber.imageHasLocation(model.attachments[0].fileURL))
        model.submit(platform: .ipados) { Self.diagnostics }
        #expect(model.isSending)
        await settle(model)
        #expect(model.phase == .finished(FiledIssue(number: 12, url: URL(string: "https://github.com/SFenton/fenton-hass-requests/issues/12")!)))
        #expect(filer.uploads == ["shot.png"])
        let report = try #require(filer.reports.first)
        #expect(report.platform == "ipados" && report.kind == "bug")
        #expect(report.media == [.init(name: "shot.png", url: "https://github.com/user-attachments/assets/1", video: false)])
        model.discardMedia()
        #expect(model.attachments.isEmpty)
    }

    @Test func failuresKeepTheFormAndFlagTokenProblems() async {
        let filer = ScriptedFiler()
        filer.submitError = FeedbackFilingError.githubProblem
        let model = await model(filer)
        fill(model)
        model.submit(platform: .ios) { Self.diagnostics }
        await settle(model)
        #expect(model.phase == .failed(FeedbackFilingError.githubProblem.errorDescription!))
        model.acknowledgeFailure()
        #expect(model.phase == .editing)
        #expect(model.title == "[Bug] Lights")
        filer.submitError = URLError(.timedOut)
        model.submit(platform: .ios) { Self.diagnostics }
        await settle(model)
        #expect(model.phase == .failed(FeedbackFilingError.network.errorDescription!))
        model.acknowledgeFailure()
        filer.submitError = FeedbackFilingError.notConfigured
        model.submit(platform: .ios) { Self.diagnostics }
        await settle(model)
        #expect(model.availability == .unavailable, "A missing integration found on Submit shows the setup notice")
    }

    @Test func stopSendingReturnsToEditing() async throws {
        let filer = ScriptedFiler()
        filer.uploadDelay = .seconds(5)
        let model = await model(filer)
        fill(model)
        await model.admit(try stagedImage(), displayName: "shot.png")
        model.submit(platform: .ios) { Self.diagnostics }
        #expect(model.phase == .sending(step: 1, total: 2))
        model.cancelSubmit()
        #expect(model.phase == .editing)
        await settle(model)
        #expect(filer.reports.isEmpty)
        model.cancelSubmit()
        model.discardMedia()
    }

    @Test func refusals() async throws {
        let model = await model()
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
        let model = await model()
        await model.importFiles(.success([original]))
        #expect(model.attachments.count == 1)
        #expect(model.attachments[0].fileURL.path.hasPrefix(FeedbackPickedMedia.stagingFolder.path))
        #expect(try FeedbackLocationScrubber.imageHasLocation(original), "The original keeps its metadata")
        await model.importFiles(.success([folder.appendingPathComponent("missing.jpg")]))
        #expect(model.attachmentMessage == FeedbackAttachmentRejection.unreadable.errorDescription)
        model.discardMedia()
    }

    @Test func servicesResolveFromTheEnvironment() async throws {
        let server = HassServer(baseURL: URL(string: "https://ha.example.com")!)
        #expect(try await FeedbackServices.resolve(["FENTON_FEEDBACK_FIXTURE": "1"], server: server, tokens: nil).filer.isAvailable())
        #expect(try await !FeedbackServices.resolve(["FENTON_FEEDBACK_FIXTURE": "unavailable"], server: server, tokens: nil).filer.isAvailable())
        let live = FeedbackServices.resolve([:], server: server, tokens: nil).filer
        #expect(live is HomeAssistantFeedbackClient)
        await #expect(throws: FeedbackFilingError.signedOut) { try await live.isAvailable() }
    }

    @Test func diagnosticsCollector() {
        let traits = FeedbackDiagnosticsCollector.Traits(dynamicTypeSize: .xLarge, colorScheme: .dark, regularWidth: true,
                                                         voiceOver: true, reduceMotion: false)
        let diagnostics = FeedbackDiagnosticsCollector.diagnostics(platform: .iphoneDuo, traits: traits,
                                                                   homeAssistant: "2026.10.1, connected")
        #expect(diagnostics.device.hasPrefix("iPhone Duo ("))
        #expect(diagnostics.accessibility == "Text xLarge, VoiceOver on, Reduce Motion off, Dark")
        #expect(diagnostics.window.contains("regular width"))
        #expect(!diagnostics.system.isEmpty && !diagnostics.app.isEmpty)
        #expect(FeedbackDiagnosticsCollector.familyName(.ios) == "iPhone" && FeedbackDiagnosticsCollector.familyName(.ipados) == "iPad")
    }

    /// Hosted renders of the Settings section, both forms (with and without a token) and the GitHub page.
    @Test func hostedRenders() async {
        let session = AppSession(tokenStore: InMemoryTokenStore(), snapshotCache: EntitySnapshotCache(
            fileURL: FileManager.default.temporaryDirectory.appending(path: "feedback-\(UUID()).json")))
        let store = EntityStore()
        let connection = HassConnection(server: .fentonHome, tokens: TokenManager(store: InMemoryTokenStore()), store: store)
        let unavailable = ScriptedFiler()
        unavailable.available = .success(false)
        let views: [AnyView] = [
            AnyView(NavigationStack { List { FeedbackSettingsSection(openForm: .constant(nil)) } }),
            AnyView(FeedbackFormSheet(kind: .bug, services: FeedbackServices(filer: ScriptedFiler()))),
            AnyView(FeedbackFormSheet(kind: .feature, services: FeedbackServices(filer: unavailable))),
            AnyView(FeedbackFieldHeader("Title", detail: "Detail")),
        ]
        for view in views {
            let hosted = view.environment(session).environment(connection).environment(store).frame(width: 402, height: 874)
            #expect(ImageRenderer(content: hosted).cgImage != nil)
        }
        let collector = FeedbackDiagnosticsCollector(platform: .ios, traits: .init(dynamicTypeSize: .large, colorScheme: .light,
                                                                                    regularWidth: false, voiceOver: false, reduceMotion: false))
        #expect(collector.collect(connection: connection).homeAssistant == "Disconnected")
    }

    @Test func settingsListHostsTheSection() {
        let host = SheetHostWindow(FeedbackSettingsSection(openForm: .constant(.bug)).feedbackFormSheet(item: .constant(nil)))
        host.settle()
        #expect(!host.hasSheet)
    }
}
