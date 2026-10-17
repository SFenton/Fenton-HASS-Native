#if os(macOS)
import AppKit
import Foundation
@testable import HassCore
import HassDesign
@testable import HassUI
import SwiftUI
import Testing

/// The Report an Issue / Request a Feature sheet in each state its model reaches, hosted in a window, and the
/// attachment strip and tiles that sit in it.
@MainActor
@Suite(.serialized)
struct FeedbackFormSheetTests {
    static let phone = CGSize(width: 402, height: 874)

    func connection() -> HassConnection {
        HassConnection(server: .fentonHome, tokens: TokenManager(store: InMemoryTokenStore()), store: EntityStore())
    }

    /// The sheet over `model`, hosted with the environment the Settings page gives it.
    func host(_ kind: FeedbackKind = .bug, model: FeedbackFormModel, size: CGSize = FeedbackFormSheetTests.phone) -> HostedWindow {
        let connection = connection()
        return HostedWindow(
            FeedbackFormSheet(kind: kind, model: model).environment(connection).environment(connection.store),
            size: size
        )
    }

    func model(_ filer: ScriptedFiler = ScriptedFiler(), kind: FeedbackKind = .bug, ready: Bool = true) async -> FeedbackFormModel {
        let model = FeedbackFormModel(kind: kind, services: FeedbackServices(filer: filer))
        if ready { await model.checkAvailability() }
        return model
    }

    func fill(_ model: FeedbackFormModel) {
        model.title = model.title + "Lights flicker"
        model.descriptionText = "They flicker when the fan starts"
        model.reproSteps = "Open Home"
        model.expectedBehavior = "Steady"
    }

    func stagedImage(_ name: String) throws -> URL {
        let folder = FeedbackPickedMedia.stagingFolder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try FeedbackUITestMedia.image(in: folder, name: name, type: .png, gps: false)
    }

    func draw(_ hosted: HostedWindow, settle: TimeInterval = 0.5) async throws -> NSBitmapImageRep {
        await hosted.settle(settle)
        return try #require(hosted.snapshot())
    }

    // MARK: States

    @Test func aFreshFormShowsThePrefilledTitleAndDisablesSubmit() async throws {
        let model = await model()
        #expect(model.title == "[Bug] " && !model.canSubmit)
        let hosted = host(model: model)
        defer { hosted.close() }
        let fresh = try await draw(hosted)
        #expect(fresh.distinctColors > 3)
        // A valid draft turns the validation line off and Submit on.
        fill(model)
        #expect(model.canSubmit)
        let filled = try await draw(hosted)
        #expect(filled.differs(from: fresh))
    }

    @Test func aFeatureRequestHasNoReproductionBoxes() async throws {
        let bug = await model(kind: .bug)
        let feature = await model(kind: .feature)
        let bugWindow = host(.bug, model: bug)
        defer { bugWindow.close() }
        let featureWindow = host(.feature, model: feature)
        defer { featureWindow.close() }
        let bugImage = try await draw(bugWindow)
        let featureImage = try await draw(featureWindow)
        #expect(bugImage.differs(from: featureImage), "the bug form has two more boxes")
    }

    @Test func aHomeAssistantWithoutTheIntegrationShowsTheSetupNotice() async throws {
        let unavailable = ScriptedFiler()
        unavailable.available = .success(false)
        let broken = await model(unavailable)
        let working = await model()
        let brokenWindow = host(model: broken)
        defer { brokenWindow.close() }
        let workingWindow = host(model: working)
        defer { workingWindow.close() }
        #expect(broken.availability == .unavailable)
        #expect(try await draw(brokenWindow).differs(from: try await draw(workingWindow)))
    }

    @Test func attachedMediaShowsAStripAndFillsTheLimit() async throws {
        let model = await model()
        let hosted = host(model: model)
        defer { hosted.close(); model.discardMedia() }
        let empty = try await draw(hosted)
        await model.admit(try stagedImage("one.png"), displayName: "one.png")
        await model.admit(try stagedImage("two.png"), displayName: "two.png")
        #expect(model.attachments.count == 2)
        let strip = try await draw(hosted, settle: 0.8)
        #expect(strip.differs(from: empty), "the strip of thumbnails appears")
        for index in 2..<FeedbackLimits.attachments { await model.admit(try stagedImage("p\(index).png"), displayName: "p\(index).png") }
        await model.admit(try stagedImage("extra.png"), displayName: "extra.png")
        #expect(model.attachmentMessage == FeedbackAttachmentRejection.tooMany.errorDescription)
        let full = try await draw(hosted)
        #expect(full.differs(from: strip), "the notice and the disabled Attach Media row show")
    }

    @Test func sendingShowsProgressAndAStopButtonWhileMediaUploads() async throws {
        let filer = ScriptedFiler()
        filer.uploadDelay = .seconds(10)
        let model = await model(filer)
        fill(model)
        await model.admit(try stagedImage("shot.png"), displayName: "shot.png")
        let hosted = host(model: model)
        defer { hosted.close(); model.cancelSubmit(); model.discardMedia() }
        let editing = try await draw(hosted)
        model.submit(platform: .ios) { FeedbackFormModelTests.diagnostics }
        #expect(model.phase == .sending(step: 1, total: 2))
        let sending = try await draw(hosted)
        #expect(sending.differs(from: editing), "the form goes read-only with a progress bar")
        model.cancelSubmit()
        #expect(model.phase == .editing)
        let back = try await draw(hosted)
        #expect(back.differs(from: sending))
    }

    @Test func aFiledReportAsksToViewItOnGitHub() async throws {
        let filer = ScriptedFiler()
        let model = await model(filer)
        fill(model)
        let hosted = host(model: model)
        defer { hosted.close() }
        await hosted.settle(0.3)
        model.submit(platform: .iphoneDuo) { FeedbackFormModelTests.diagnostics }
        for _ in 0..<100 where model.isSending { try? await Task.sleep(for: .milliseconds(10)) }
        guard case let .finished(issue) = model.phase else { Issue.record("expected the report to be filed, got \(model.phase)"); return }
        #expect(issue.number == 12)
        await hosted.settle(1.0)
        #expect(hosted.window.attachedSheet != nil || !hosted.window.sheets.isEmpty, "the Report Sent alert is up")
    }

    @Test func aFailedSendNamesTheProblemAndKeepsTheDraft() async throws {
        let filer = ScriptedFiler()
        filer.submitError = FeedbackFilingError.githubProblem
        let model = await model(filer)
        fill(model)
        let hosted = host(model: model)
        defer { hosted.close() }
        await hosted.settle(0.3)
        model.submit(platform: .ios) { FeedbackFormModelTests.diagnostics }
        for _ in 0..<100 where model.isSending { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(model.phase == .failed(FeedbackFilingError.githubProblem.errorDescription!))
        await hosted.settle(1.0)
        #expect(!hosted.window.sheets.isEmpty, "the Couldn't Send alert is up")
        model.acknowledgeFailure()
        #expect(model.phase == .editing && model.title.contains("Lights flicker"))
    }

    @Test(arguments: [DynamicTypeSize.large, .accessibility5])
    func theFormLaysOutAtEveryTextSize(size: DynamicTypeSize) async throws {
        let model = await model()
        fill(model)
        await model.admit(try stagedImage("shot.png"), displayName: "shot.png")
        let connection = connection()
        let hosted = HostedWindow(
            FeedbackFormSheet(kind: .bug, model: model).environment(connection).environment(connection.store).dynamicTypeSize(size),
            size: Self.phone
        )
        defer { hosted.close(); model.discardMedia() }
        #expect(try await draw(hosted).distinctColors > 3)
    }

    // MARK: Attachment tiles

    @Test func tilesShowAThumbnailOrAPlaceholderPerKind() async throws {
        let image = try stagedImage("thumb.png")
        defer { try? FileManager.default.removeItem(at: image.deletingLastPathComponent()) }
        let photo = FeedbackAttachment(fileURL: image, filename: "thumb.png", mimeType: "image/png", byteCount: 100, isVideo: false)
        let missing = FeedbackAttachment(fileURL: image.deletingLastPathComponent().appendingPathComponent("gone.mov"),
                                         filename: "gone.mov", mimeType: "video/quicktime", byteCount: 100, isVideo: true)
        #expect(photo.accessibilityLabel(position: 1).contains("thumb.png"))
        var opened = 0, removed = 0
        func tile(_ attachment: FeedbackAttachment, _ position: Int) -> some View {
            FeedbackAttachmentTile(attachment: attachment, position: position, onOpen: { opened += 1 }, onRemove: { removed += 1 })
        }
        let hosted = HostedWindow(HStack { tile(photo, 1); tile(missing, 2) }.padding(), size: CGSize(width: 300, height: 140))
        defer { hosted.close() }
        // A photo loads its own thumbnail; a movie that can't be read keeps the film placeholder.
        let loaded = try await draw(hosted, settle: 1.5)
        let placeholders = HostedWindow(HStack { tile(missing, 1); tile(missing, 2) }.padding(), size: CGSize(width: 300, height: 140))
        defer { placeholders.close() }
        let bare = try await draw(placeholders, settle: 1.5)
        #expect(loaded.differs(from: bare), "the photo's thumbnail replaces its placeholder")
        // The strip lays the same tiles out in a row.
        let strip = FeedbackAttachmentStrip(attachments: [photo, missing]) { _ in removed += 1 }
        let stripWindow = HostedWindow(strip, size: CGSize(width: 300, height: 140))
        defer { stripWindow.close() }
        #expect(try await draw(stripWindow, settle: 1.0).distinctColors > 2)
        _ = (opened, removed)
    }
}

/// Presses the feedback sheet's controls through the accessibility tree.
@MainActor
@Suite(.serialized, .enabled(if: AXWindow.isAvailable, "Needs accessibility permission for the test host"))
struct FeedbackFormFlowTests {
    @Test func theFormListsItsBoxesAndSubmitFollowsTheDraft() async throws {
        let connection = HassConnection(server: .fentonHome, tokens: TokenManager(store: InMemoryTokenStore()), store: EntityStore())
        let model = FeedbackFormModel(kind: .bug, services: FeedbackServices(filer: ScriptedFiler()))
        await model.checkAvailability()
        let driver = AXWindow(
            FeedbackFormSheet(kind: .bug, model: model).environment(connection).environment(connection.store),
            size: FeedbackFormSheetTests.phone
        )
        defer { driver.close() }
        let nodes = await driver.wait { $0.contains { $0.identifier == "feedback.field.title" } }
        for id in ["feedback.field.title", "feedback.field.description", "feedback.field.repro", "feedback.field.expected",
                   "feedback.attach", "feedback.validation", "feedback.submit", "feedback.close"] {
            #expect(nodes.contains { $0.identifier == id }, "\(id)")
        }
        #expect(nodes.first { $0.identifier == "feedback.field.title" }?.value == "[Bug] ")
        #expect(nodes.first { $0.identifier == "feedback.submit" }?.isEnabled == false)
        model.title = "[Bug] Lights"
        model.descriptionText = "Flicker"
        model.reproSteps = "Open Home"
        model.expectedBehavior = "Steady"
        let ready = await driver.wait {
            $0.contains { $0.identifier == "feedback.submit" && $0.isEnabled } && !$0.contains { $0.identifier == "feedback.validation" }
        }
        #expect(ready.contains { $0.identifier == "feedback.submit" && $0.isEnabled })
        #expect(!ready.contains { $0.identifier == "feedback.validation" }, "no reason left to show")
    }

    @Test func typingInTheBoxesFillsTheDraftAndSubmitFiles() async throws {
        let connection = HassConnection(server: .fentonHome, tokens: TokenManager(store: InMemoryTokenStore()), store: EntityStore())
        let filer = ScriptedFiler()
        let model = FeedbackFormModel(kind: .bug, services: FeedbackServices(filer: filer))
        await model.checkAvailability()
        let driver = AXWindow(
            FeedbackFormSheet(kind: .bug, model: model).environment(connection).environment(connection.store),
            size: FeedbackFormSheetTests.phone
        )
        defer { driver.close() }
        #expect(await driver.type("[Bug] Lights flicker", into: "feedback.field.title"))
        #expect(await driver.type("They flicker when the fan starts", into: "feedback.field.description"))
        #expect(await driver.type("Open Home", into: "feedback.field.repro"))
        #expect(await driver.type("Steady light", into: "feedback.field.expected"))
        let typed = await driver.wait { _ in model.canSubmit }
        _ = typed
        #expect(model.title == "[Bug] Lights flicker" && model.descriptionText.hasPrefix("They flicker"))
        #expect(model.reproSteps == "Open Home" && model.expectedBehavior == "Steady light")
        #expect(model.canSubmit)
        // Submit files it through Home Assistant and the Report Sent alert offers Done.
        #expect(await driver.press("feedback.submit") { _ in !filer.reports.isEmpty })
        let report = try #require(filer.reports.first)
        #expect(report.title == "[Bug] Lights flicker" && report.kind == "bug")
        let alert = await driver.wait { $0.contains { $0.identifier == "feedback.done" } }
        #expect(alert.contains { $0.identifier == "feedback.view" } && alert.contains { $0.identifier == "feedback.done" })
    }

    @Test func removingAnAttachmentDropsItsTileAndItsCopy() async throws {
        let connection = HassConnection(server: .fentonHome, tokens: TokenManager(store: InMemoryTokenStore()), store: EntityStore())
        let model = FeedbackFormModel(kind: .feature, services: FeedbackServices(filer: ScriptedFiler()))
        await model.checkAvailability()
        let folder = FeedbackPickedMedia.stagingFolder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        await model.admit(try FeedbackUITestMedia.image(in: folder, name: "first.png", type: .png, gps: false), displayName: "first.png")
        #expect(model.attachments.count == 1)
        let copy = model.attachments[0].fileURL
        let driver = AXWindow(
            FeedbackFormSheet(kind: .feature, model: model).environment(connection).environment(connection.store),
            size: FeedbackFormSheetTests.phone
        )
        defer { driver.close(); model.discardMedia() }
        let tile = await driver.waitFor("feedback.attachment.1")
        #expect(tile?.spoken.contains("first.png") == true, "the thumbnail reads its file name")
        let removed = await driver.press("feedback.attachment.1.remove") { _ in model.attachments.isEmpty }
        #expect(removed, "pressing the tile's remove button drops the attachment")
        #expect(!FileManager.default.fileExists(atPath: copy.path), "and deletes the app's copy")
    }
}
#endif
