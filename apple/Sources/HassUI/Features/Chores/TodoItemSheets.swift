import HassCore
import HassDesign
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Add grocery item

/// Adds an item to the grocery list with `todo.add_item` (web `CreateGroceryItemSheet`).
struct AddGroceryItemSheet: View {
    var entityId: String

    @Environment(ChoresModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var item = ""
    @State private var submitting = false
    @State private var error: String?
    @FocusState private var focused: Bool

    private var trimmed: String { item.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                TodoSheetErrorSection(error: error)
                Section {
                    TextField("Item", text: $item)
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit { Task { await add() } }
                        .accessibilityIdentifier("grocery.item")
                }
            }
            .disabled(submitting)
            .modalChrome()
            .navigationTitle("Add Grocery Item")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(submitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(submitting ? "Adding…" : "Add") { Task { await add() } }
                        .disabled(trimmed.isEmpty || submitting)
                        .accessibilityIdentifier("grocery.add")
                }
            }
        }
        .hassSheet()
        .interactiveDismissDisabled(submitting)
        .onAppear { focused = true }
    }

    private func add() async {
        guard !trimmed.isEmpty, !submitting else { return }
        submitting = true
        error = nil
        defer { submitting = false }
        do {
            try await model.service.callService("todo", "add_item", data: ["entity_id": entityId, "item": trimmed])
            dismiss()
        } catch {
            self.error = TodoListController.message(error, fallback: "Unable to add grocery item")
        }
    }
}

// MARK: - Add admin to-do

/// Adds an admin to-do, with up to four images (web `CreateTodoItemSheet`). Without images it is a plain
/// `todo.add_item`; with images it posts to the dashboard integration, which files them on the GitHub issue.
struct AddAdminTodoSheet: View {
    var entityId: String

    @Environment(ChoresModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var task = ""
    @State private var selection: [PhotosPickerItem] = []
    @State private var images: [SelectedImage] = []
    @State private var submitting = false
    @State private var error: String?

    /// An image read from the picker.
    struct SelectedImage: Identifiable {
        let id = UUID()
        var upload: AdminTodoUpload.Image
    }

    private var trimmed: String { task.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                TodoSheetErrorSection(error: error)
                Section {
                    TextField("Task", text: $task, axis: .vertical)
                        .lineLimit(1...4)
                        .onChange(of: task) { _, value in if value.count > 1000 { task = String(value.prefix(1000)) } }
                        .accessibilityIdentifier("adminTodo.task")
                } footer: {
                    Text("This issue is synchronized from the dashboard Admin To-Do list. The repository is public.")
                }
                Section {
                    ForEach(images) { image in
                        AdminTodoImageRow(image: image.upload) {
                            images.removeAll { $0.id == image.id }
                            selection = []
                        }
                    }
                    PhotosPicker(selection: $selection, maxSelectionCount: AdminTodoUpload.maxImages, matching: .images) {
                        Label(images.isEmpty ? "Add Images" : "Choose Different Images", systemImage: "photo.on.rectangle.angled")
                    }
                    // The app accent measured 3.3:1 on the modal background (iPad audit, 2026-10-13).
                    .tint(HassTokens.Ink.action)
                    .accessibilityIdentifier("adminTodo.images")
                } header: {
                    Text("Images")
                } footer: {
                    Text("Add up to four PNG, JPEG, or WebP images, 10 MB each.")
                }
            }
            .disabled(submitting)
            .modalChrome()
            .navigationTitle("Add Task")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(submitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(submitting ? "Adding…" : "Add") { Task { await add() } }
                        .disabled(trimmed.isEmpty || submitting)
                        .accessibilityIdentifier("adminTodo.add")
                }
            }
            .onChange(of: selection) { _, items in Task { await readImages(items) } }
        }
        .interactiveDismissDisabled(submitting)
    }

    private func readImages(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        var read: [AdminTodoUpload.Image] = []
        for (index, item) in items.enumerated() {
            let type = item.supportedContentTypes.first { AdminTodoUpload.mimeTypes.contains($0.preferredMIMEType ?? "") }
                ?? item.supportedContentTypes.first
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let mime = type?.preferredMIMEType ?? "application/octet-stream"
            let ext = type?.preferredFilenameExtension ?? "img"
            read.append(AdminTodoUpload.Image(data: data, filename: "image-\(index + 1).\(ext)", mimeType: mime))
        }
        if let problem = AdminTodoUpload.validationError(count: read.count, sizes: read.map(\.data.count), mimeTypes: read.map(\.mimeType)) {
            images = []
            error = problem
        } else {
            images = read.map { SelectedImage(upload: $0) }
            error = nil
        }
    }

    private func add() async {
        guard !trimmed.isEmpty, !submitting else { return }
        submitting = true
        error = nil
        defer { submitting = false }
        do {
            if images.isEmpty {
                try await model.service.callService("todo", "add_item", data: ["entity_id": entityId, "item": trimmed])
            } else {
                let upload = AdminTodoUpload(entityId: entityId, item: trimmed, images: images.map(\.upload))
                try await model.service.uploadAdminTodo(upload, accessToken: try await model.accessToken())
            }
            dismiss()
        } catch {
            self.error = "Unable to add this task. Try again."
        }
    }
}

/// A picked image: thumbnail, name and a remove button.
struct AdminTodoImageRow: View {
    var image: AdminTodoUpload.Image
    var onRemove: () -> Void

    var body: some View {
        HStack(spacing: HassTokens.Spacing.m) {
            thumbnail
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            Text(image.filename)
                .foregroundStyle(HassTokens.Ink.primary)
            Spacer()
            Button(role: .destructive, action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .frame(minWidth: HassTokens.minTarget, minHeight: HassTokens.minTarget)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(image.filename)")
        }
    }

    @ViewBuilder private var thumbnail: some View {
        #if canImport(UIKit)
        if let ui = UIImage(data: image.data) {
            SwiftUI.Image(uiImage: ui).resizable().scaledToFill()
        } else {
            SwiftUI.Image(systemName: "photo")
        }
        #else
        SwiftUI.Image(systemName: "photo")
        #endif
    }
}

// MARK: - Rename admin to-do

/// Renames an admin to-do with `todo.update_item` `rename` (web `EditTodoItemSheet`).
struct RenameTodoItemSheet: View {
    var target: AdminTodoEditTarget
    var onSaved: () -> Void = {}

    @Environment(ChoresModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String
    @State private var submitting = false
    @State private var error: String?

    init(target: AdminTodoEditTarget, onSaved: @escaping () -> Void = {}) {
        self.target = target
        self.onSaved = onSaved
        _draft = State(initialValue: target.originalTitle)
    }

    private var trimmed: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Savable when the item has an identity and the trimmed name is new and not empty.
    static func canSave(target: AdminTodoEditTarget, draft: String) -> Bool {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return target.itemUid != nil && !trimmed.isEmpty && trimmed != target.originalTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                TodoSheetErrorSection(error: error)
                if target.itemUid == nil {
                    TodoSheetErrorSection(error: "This task cannot be edited because its Home Assistant identity is unavailable.")
                }
                Section {
                    TextField("Task Name", text: $draft, axis: .vertical)
                        .lineLimit(1...4)
                        .accessibilityIdentifier("renameTodo.name")
                    Button("Reset") {
                        draft = target.originalTitle
                        error = nil
                    }
                    .disabled(draft == target.originalTitle && error == nil)
                    .accessibilityIdentifier("renameTodo.reset")
                } footer: {
                    Text("This issue is synchronized from the dashboard Admin To-Do list. The repository is public.")
                }
            }
            .disabled(submitting)
            .modalChrome()
            .navigationTitle("Edit Task")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(submitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(submitting ? "Saving…" : "Save") { Task { await save() } }
                        .disabled(submitting || !Self.canSave(target: target, draft: draft))
                        .accessibilityIdentifier("renameTodo.save")
                }
            }
        }
        .hassSheet()
        .interactiveDismissDisabled(submitting)
    }

    private func save() async {
        guard let uid = target.itemUid, Self.canSave(target: target, draft: draft), !submitting else { return }
        submitting = true
        error = nil
        defer { submitting = false }
        do {
            try await model.service.callService("todo", "update_item", data: ["entity_id": target.todoEntityId, "item": uid, "rename": trimmed])
            onSaved()
            dismiss()
        } catch {
            self.error = TodoListController.message(error, fallback: "Unable to update task.")
        }
    }
}

// MARK: - Shared

/// An error line at the top of a todo form.
struct TodoSheetErrorSection: View {
    var error: String?

    var body: some View {
        if let error {
            Section {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .foregroundStyle(HassTokens.Ink.primary)
                    .accessibilityIdentifier("todoSheet.error")
            }
        }
    }
}
