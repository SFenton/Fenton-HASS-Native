import HassCore
import HassDesign
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

/// Report an Issue / Request a Feature form, ported from FestivalNativeApps' `FeedbackFormSheet`
/// (`.agents/controls/feedback-form/`).
///
/// A scoped task in a sheet with Cancel (leading) and Submit (trailing) rather than a Done button,
/// because closing can lose typed input. HIG (Sheets): "Single-view sheets: Cancel on the top toolbar's
/// leading edge; Done, when present, trailing." HIG (Modality): "If either a dismiss gesture or button
/// could lose user-generated content, get confirmation before closing".
struct FeedbackFormSheet: View {
    private let kind: FeedbackKind
    @State private var model: FeedbackFormModel
    @State private var confirmingDiscard = false
    @State private var showingPhotos = false
    @State private var showingFiles = false
    @State private var photoSelection: [PhotosPickerItem] = []
    /// The focused box, cleared before sending so the keyboard closes.
    @FocusState private var focusedField: String?
    @Environment(HassConnection.self) private var connection
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Creates an empty form.
    init(kind: FeedbackKind, services: FeedbackServices) {
        self.kind = kind
        _model = State(initialValue: FeedbackFormModel(kind: kind, services: services))
    }

    var body: some View {
        NavigationStack {
            form
                .modalChrome()
                .navigationTitle(kind.formTitle)
                .inlineNavigationTitle()
                .toolbar { toolbar }
        }
        .interactiveDismissDisabled(model.isSending || model.hasUnsavedInput)
        #if os(iOS)
        .background(SheetDismissAttemptObserver { requestClose() })
        #endif
        .photosPicker(
            isPresented: $showingPhotos, selection: $photoSelection,
            maxSelectionCount: max(1, FeedbackLimits.attachments - model.attachments.count),
            matching: .any(of: [.images, .videos]), preferredItemEncoding: .current
        )
        .onChange(of: photoSelection) { _, items in
            guard !items.isEmpty else { return }
            photoSelection = []
            Task { await model.importPhotos(items) }
        }
        .fileImporter(isPresented: $showingFiles, allowedContentTypes: [.image, .movie], allowsMultipleSelection: true) { result in
            Task { await model.importFiles(result) }
        }
        .alert(successTitle, isPresented: finishedBinding, presenting: filedIssue) { issue in
            Button("View on GitHub") {
                openURL(issue.url)
                close()
            }
            .accessibilityIdentifier("feedback.view")
            Button("Done", role: .cancel, action: close)
                .accessibilityIdentifier("feedback.done")
        } message: { issue in
            Text("Thank you! It was filed as issue #\(issue.number). The triage agent will pick it up on its next run.")
        }
        .alert("Couldn't Send", isPresented: failedBinding) {
            Button("OK", role: .cancel) { model.acknowledgeFailure() }
        } message: {
            Text(failureMessage)
        }
        .task { await model.checkAvailability() }
    }

    // MARK: - Form

    private var form: some View {
        Form {
            if model.availability == .unavailable { setupSection }
            Section {
                TextField("Title", text: $model.title)
                    .frame(minHeight: HassTokens.minTarget)
                    .accessibilityLabel("Title")
                    .accessibilityHint(titleDetail)
                    .accessibilityIdentifier("feedback.field.title")
                    .focused($focusedField, equals: "title")
                    .disabled(model.isSending)
                    #if os(iOS)
                    .textInputAutocapitalization(.sentences)
                    #endif
            } header: {
                FeedbackFieldHeader("Title", detail: titleDetail)
            }
            textBox("Description", detail: descriptionDetail, text: $model.descriptionText, identifier: "feedback.field.description")
            if kind.includesReproduction {
                textBox("Steps to Reproduce", detail: "List the steps that make it happen, one per line.",
                        text: $model.reproSteps, identifier: "feedback.field.repro")
                textBox("Expected Behavior", detail: "What did you expect to happen instead?",
                        text: $model.expectedBehavior, identifier: "feedback.field.expected")
            }
            mediaSection
            if model.isSending {
                progressSection
            } else if let reason = model.blockingReason {
                Section {
                    Text(reason)
                        .font(.footnote)
                        .foregroundStyle(HassTokens.Ink.primary)
                        .accessibilityIdentifier("feedback.validation")
                }
            }
        }
        .formStyle(.grouped)
        .scrollDismissesKeyboard(.interactively)
    }

    private func textBox(_ label: String, detail: String, text: Binding<String>, identifier: String) -> some View {
        Section {
            TextEditor(text: text)
                .frame(minHeight: 96)
                .accessibilityLabel(label)
                .accessibilityHint(detail)
                .accessibilityIdentifier(identifier)
                .focused($focusedField, equals: identifier)
                .disabled(model.isSending)
        } header: {
            FeedbackFieldHeader(label, detail: detail)
        }
    }

    private var mediaSection: some View {
        Section {
            if !model.attachments.isEmpty {
                FeedbackAttachmentStrip(attachments: model.attachments) { model.remove($0) }
                    .disabled(model.isSending)
            }
            Menu {
                Button("Photo Library", systemImage: "photo.on.rectangle") { showingPhotos = true }
                    .accessibilityIdentifier("feedback.attach.media")
                Button("Choose File…", systemImage: "folder") { showingFiles = true }
                    .accessibilityIdentifier("feedback.attach.files")
            } label: {
                // The whole row is the hit target, not only the label's glyphs.
                Label("Attach Media", systemImage: "paperclip")
                    .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .disabled(model.attachments.count >= FeedbackLimits.attachments || model.isSending)
            .accessibilityIdentifier("feedback.attach")
            if model.importing > 0 {
                ProgressView("Adding media…")
                    .progressViewStyle(.arc(.compact))
                    .accessibilityIdentifier("feedback.attach.progress")
            }
            if let message = model.attachmentMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(HomeAssistantSettingsView.destructiveInk)
                    .accessibilityIdentifier("feedback.attachments.notice")
            }
        } header: {
            FeedbackFieldHeader(
                "Media",
                detail: "Optional screenshots or screen recordings: up to \(FeedbackLimits.attachments) photos or videos. Large videos are compressed, and location is removed."
            )
        }
    }

    private var progressSection: some View {
        Section {
            ProgressView(value: progress) { Text(progressText) }
                .accessibilityIdentifier("feedback.progress")
            if canStop {
                Button("Stop Sending", role: .destructive) { model.cancelSubmit() }
                    .foregroundStyle(HomeAssistantSettingsView.destructiveInk)
                    .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget, alignment: .leading)
                    .accessibilityIdentifier("feedback.stop")
            }
        }
    }

    /// Shown while Home Assistant can't file reports: what's missing and who can add it (the shared
    /// ``InfoBox``, `.agents/patterns/info-box.md`).
    private var setupSection: some View {
        Section {
            InfoBox(
                title: "Reporting isn't set up yet",
                message: "Reports are filed through Home Assistant. Whoever manages it can add the Fenton Home Feedback integration in Settings → Devices & services.",
                tone: .neutral
            )
            .accessibilityIdentifier("feedback.setup")
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel", action: requestClose)
                .accessibilityIdentifier("feedback.close")
                // Anchored to Cancel so the popover-style dialog points at it.
                .confirmationDialog(discardTitle, isPresented: $confirmingDiscard, titleVisibility: .visible) {
                    Button("Discard Changes", role: .destructive, action: close)
                        .accessibilityIdentifier("feedback.discard.confirm")
                    Button("Keep Editing", role: .cancel) {}
                        .accessibilityIdentifier("feedback.discard.cancel")
                } message: {
                    Text("Your text and attached media will be lost.")
                }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Submit", action: submit)
                .disabled(!model.canSubmit)
                .accessibilityIdentifier("feedback.submit")
        }
    }

    // MARK: - Actions

    /// Cancel, Escape or a swipe: confirm first when something would be lost.
    private func requestClose() {
        if model.hasUnsavedInput || model.isSending {
            confirmingDiscard = true
        } else {
            close()
        }
    }

    private func close() {
        model.discardMedia()
        dismiss()
    }

    private func submit() {
        focusedField = nil
        let collector = FeedbackDiagnosticsCollector(platform: platform, traits: .init(
            dynamicTypeSize: dynamicTypeSize, colorScheme: colorScheme,
            regularWidth: horizontalSizeClass == .regular, voiceOver: voiceOver, reduceMotion: reduceMotion
        ))
        let connection = connection
        model.submit(platform: platform) { collector.collect(connection: connection) }
    }

    private var platform: FeedbackPlatform {
        #if canImport(UIKit)
        FeedbackPlatform.resolve(isPad: UIDevice.current.userInterfaceIdiom == .pad, hasHinge: HingePresence.shared.hasHinge)
        #else
        .ios
        #endif
    }

    // MARK: - Text

    private var titleDetail: String {
        "Keep the \(kind.titlePrefix.trimmingCharacters(in: .whitespaces)) prefix and "
            + (kind == .bug ? "sum up the problem in a few words." : "name the idea in a few words.")
    }

    private var descriptionDetail: String {
        kind == .bug
            ? "What went wrong? Say which page you were on and what you saw."
            : "Describe the feature and how it would help."
    }

    private var discardTitle: String { "Discard this \(kind.noun)?" }

    private var successTitle: String { kind == .bug ? "Report Sent" : "Request Sent" }

    private var progressText: String {
        guard case let .sending(step, total) = model.phase else { return "" }
        return step < total ? "Uploading media \(step) of \(total - 1)…" : "Filing your \(kind.noun) on GitHub…"
    }

    private var progress: Double {
        guard case let .sending(step, total) = model.phase, total > 0 else { return 0 }
        return Double(step - 1) / Double(total)
    }

    /// Stopping is offered only while media uploads: once the issue request is out, it may be filed.
    private var canStop: Bool {
        guard case let .sending(step, total) = model.phase else { return false }
        return step < total
    }

    private var filedIssue: FiledIssue? {
        if case let .finished(issue) = model.phase { return issue }
        return nil
    }

    private var finishedBinding: Binding<Bool> {
        Binding(get: { filedIssue != nil }, set: { _ in })
    }

    private var failureMessage: String {
        if case let .failed(message) = model.phase { return message }
        return ""
    }

    private var failedBinding: Binding<Bool> {
        Binding(
            get: { if case .failed = model.phase { true } else { false } },
            set: { if !$0 { model.acknowledgeFailure() } }
        )
    }
}
