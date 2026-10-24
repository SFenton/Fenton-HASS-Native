import HassCore
import HassDesign
import SwiftUI

/// Create or edit a DoneTick task (web `CreateDonetickTaskSheet` + `DonetickTaskFormPage`).
///
/// Creating sends `donetick.create_task_form`; editing loads the task with `donetick.get_task`, saves with
/// `donetick.update_task_form` and can delete it (`todo.remove_item`) after a confirmation.
struct DonetickTaskSheet: View {
    enum Mode: Hashable {
        case create(defaultAssignee: String)
        case edit(DonetickEditTarget)
    }

    var mode: Mode
    var onSaved: () -> Void = {}

    @Environment(ChoresModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var form: DonetickTaskForm
    @State private var initialForm: DonetickTaskForm
    @State private var loaded: Bool
    @State private var busy: Busy?
    @State private var error: String?
    @State private var confirmsDelete = false
    @State private var taskName = ""

    enum Busy { case saving, deleting }

    init(mode: Mode, onSaved: @escaping () -> Void = {}) {
        self.mode = mode
        self.onSaved = onSaved
        let initial: DonetickTaskForm
        if case let .create(defaultAssignee) = mode { initial = DonetickTaskForm(defaultAssignee: defaultAssignee) } else { initial = DonetickTaskForm() }
        _form = State(initialValue: initial)
        _initialForm = State(initialValue: initial)
        _loaded = State(initialValue: mode.editTarget == nil)
    }

    var body: some View {
        NavigationStack {
            Group {
                if loaded {
                    DonetickTaskFormFields(form: $form, editing: mode.editTarget != nil, viewer: model.viewer, error: error,
                                           onDelete: mode.editTarget == nil ? nil : { confirmsDelete = true })
                        .disabled(busy != nil)
                } else if let error {
                    ContentUnavailableView("Unable to Load Task", systemImage: "exclamationmark.triangle", description: Text(error))
                } else {
                    ProgressView("Loading task").progressViewStyle(.arc).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .modalChrome()
            .navigationTitle(mode.editTarget == nil ? "New Task" : "Edit Task")
            .inlineNavigationTitle()
            // An edit sheet (direction G, Sheets; mockup n5-new-task): circle x Cancel, filled check Create or Save.
            .toolbar {
                SheetCancelItem(identifier: "task.cancel", isEnabled: busy == nil) { dismiss() }
                SheetConfirmItem(mode.editTarget == nil ? "Create" : "Save", isEnabled: canSave, isBusy: busy == .saving,
                                 busyTitle: mode.editTarget == nil ? "Creating" : "Saving", identifier: "task.save") {
                    Task { await save() }
                }
            }
            .confirmationDialog("Delete \(taskName)?", isPresented: $confirmsDelete, titleVisibility: .visible) {
                Button("Delete Task", role: .destructive) { Task { await delete() } }
                    .accessibilityIdentifier("task.delete.confirm")
            }
        }
        .interactiveDismissDisabled(busy != nil)
        .task { await load() }
    }

    /// A new task needs a name; an edit also needs a change (``SheetEditState``).
    private var canSave: Bool {
        SheetEditState.canConfirm(isValid: loaded && !form.trimmedName.isEmpty,
                                  hasChanges: mode.editTarget == nil || form != initialForm, isBusy: busy != nil)
    }

    // MARK: Actions

    private func load() async {
        guard let target = mode.editTarget, !loaded else { return }
        do {
            let response = try await model.service.callServiceForResponse("donetick", "get_task", data: [
                "config_entry_id": target.todoEntityId, "task_id": target.taskId,
            ])
            let task = try DonetickTask(response: response)
            form = DonetickTaskForm(task: task)
            initialForm = form
            taskName = task.name
            loaded = true
        } catch {
            self.error = TodoListController.message(error, fallback: "Unable to load task")
        }
    }

    private func save() async {
        guard canSave else { return }
        busy = .saving
        error = nil
        defer { busy = nil }
        do {
            if let target = mode.editTarget {
                try await model.service.callService("donetick", "update_task_form", data: form.serviceData(
                    initial: initialForm, taskId: target.taskId, configEntryId: target.todoEntityId))
            } else {
                try await model.service.callService("donetick", "create_task_form", data: form.serviceData())
            }
            onSaved()
            dismiss()
        } catch {
            self.error = TodoListController.message(error, fallback: mode.editTarget == nil ? "Unable to create task" : "Unable to save task")
        }
    }

    private func delete() async {
        guard let target = mode.editTarget, busy == nil else { return }
        busy = .deleting
        error = nil
        defer { busy = nil }
        do {
            try await model.service.callService("todo", "remove_item", data: ["entity_id": target.todoEntityId, "item": target.itemUid])
            onSaved()
            dismiss()
        } catch {
            self.error = TodoListController.message(error, fallback: "Unable to delete task")
        }
    }
}

extension DonetickTaskSheet.Mode {
    var editTarget: DonetickEditTarget? {
        if case let .edit(target) = self { return target }
        return nil
    }
}

// MARK: - Fields

/// The task form's fields (web `DonetickTaskFormBody`), in a grouped `Form`.
struct DonetickTaskFormFields: View {
    @Binding var form: DonetickTaskForm
    var editing: Bool
    var viewer: ChoresConfig.Resident?
    var error: String?
    var onDelete: (() -> Void)?
    @FocusState private var repeatFocused: Bool

    /// What the Task Name field is for.
    static let nameFooter = "A short name for the chore, as it appears in your lists. For example, “Take out the recycling”."
    /// What the Description field is for.
    static let descriptionFooter = "Optional. Add steps, notes or where to find supplies. It shows with the task when you open it."

    var body: some View {
        // Grouped as in the mockups (n5-new-task): what, who, when, then vacation.
        Form {
            if let error {
                Section {
                    InlineAlert(error, severity: .error)
                        .accessibilityIdentifier("task.error")
                }
            }
            // Two fields, each with its own header and footer saying what goes in it (owner, 2026-10-16).
            Section {
                TextField("Task Name", text: $form.name)
                    .accessibilityIdentifier("task.name")
            } header: {
                FormHeader("Task Name")
            } footer: {
                FormFooter(Self.nameFooter)
                    .accessibilityIdentifier("task.name.footer")
            }
            Section {
                TextField("Description", text: $form.description, axis: .vertical)
                    .lineLimit(3...8)
                    .accessibilityIdentifier("task.description")
            } header: {
                FormHeader("Description")
            } footer: {
                FormFooter(Self.descriptionFooter)
                    .accessibilityIdentifier("task.description.footer")
            }
            Section {
                Picker("Assignee", selection: $form.assignee) {
                    ForEach(form.assignees(viewer: viewer)) { Text($0.label).tag($0.value) }
                }
                .accessibilityIdentifier("task.assignee")
                Picker("Priority", selection: $form.priority) {
                    ForEach(DonetickTaskForm.priorities) { Text($0.label).tag($0.value) }
                }
                .accessibilityIdentifier("task.priority")
            }
            Section {
                Toggle("Due Date", isOn: DonetickDueBinding.hasDate($form))
                    .accessibilityIdentifier("task.hasDueDate")
                if !form.dueDate.isEmpty {
                    DatePicker("Date", selection: DonetickDueBinding.date($form), displayedComponents: .date)
                        .accessibilityIdentifier("task.dueDate")
                }
                Toggle("Due Time", isOn: DonetickDueBinding.hasTime($form))
                    .accessibilityIdentifier("task.hasDueTime")
                if !form.dueTime.isEmpty {
                    DatePicker("Time", selection: DonetickDueBinding.time($form), displayedComponents: .hourAndMinute)
                        .accessibilityIdentifier("task.dueTime")
                }
                // A pop-up menu anchored over the row (direction G, Controls: "Choosing one option").
                Picker("Repeat", selection: Binding(get: { form.recurrence }, set: { form.setRecurrence($0) })) {
                    ForEach(DonetickTaskForm.recurrences(editing: editing)) { Text($0.label).tag($0.value) }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("task.recurrence")
            }
            if form.showsCustomInterval {
                Section {
                    LabeledContent("Repeat Every") {
                        TextField("1", text: Binding(get: { form.recurrenceInterval }, set: { form.setRepeatEvery($0) }))
                            .multilineTextAlignment(.trailing)
                            .focused($repeatFocused)
                            .numericKeyboard()
                            .accessibilityIdentifier("task.repeatEvery")
                    }
                    Picker("Interval Unit", selection: $form.recurrenceUnit) {
                        ForEach(DonetickTaskForm.recurrenceUnits) { Text($0.label).tag($0.value) }
                    }
                    .accessibilityIdentifier("task.recurrenceUnit")
                } footer: {
                    FormFooter("How often to repeat: every 1 to 365 days, weeks, months, or years.")
                }
                .onChange(of: repeatFocused) { _, focused in if !focused { form.normalizeRepeatEvery() } }
            }
            if form.showsRecurrenceDays {
                Section {
                    ForEach(DonetickTaskForm.weekdays) { day in
                        let selected = form.recurrenceDays.contains(day.value)
                        Button { form.toggleDay(day.value) } label: {
                            HStack {
                                Text(day.label).foregroundStyle(HassTokens.Ink.primary)
                                Spacer()
                                if selected { Image(systemName: "checkmark").foregroundStyle(HassTokens.Ink.action) }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? [.isSelected] : [])
                        .accessibilityIdentifier("task.day.\(day.value)")
                    }
                } header: {
                    FormHeader("Days of Week")
                }
            }
            Section {
                Toggle("Hide While On Vacation", isOn: $form.hideOnVacation)
                    .accessibilityIdentifier("task.hideOnVacation")
            } footer: {
                FormFooter("This task will not show up in your chores lists while Vacation Mode is on.")
            }
            if let onDelete {
                Section {
                    Button("Delete Task", role: .destructive, action: onDelete)
                        .foregroundStyle(HassTokens.Ink.danger)
                        .accessibilityIdentifier("task.delete")
                }
            }
        }
    }
}

/// Bindings between the form's `yyyy-MM-dd` / `HH:mm` strings and date pickers in the device's time zone.
enum DonetickDueBinding {
    /// The two formats the form uses, built once: a formatter per binding read was allocated on every body pass.
    private nonisolated(unsafe) static let dateFormatter = makeFormatter("yyyy-MM-dd")
    private nonisolated(unsafe) static let timeFormatter = makeFormatter("HH:mm")

    private static func makeFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = format
        return formatter
    }

    static func formatter(_ format: String) -> DateFormatter {
        switch format {
        case "yyyy-MM-dd": dateFormatter
        case "HH:mm": timeFormatter
        default: makeFormatter(format)
        }
    }

    /// Turning the date on picks today; off clears it.
    static func hasDate(_ form: Binding<DonetickTaskForm>, now: Date = .now) -> Binding<Bool> {
        Binding(get: { !form.wrappedValue.dueDate.isEmpty },
                set: { form.wrappedValue.dueDate = $0 ? formatter("yyyy-MM-dd").string(from: now) : "" })
    }

    /// Turning the time on picks noon (the web's default when only a date is set); off clears it.
    static func hasTime(_ form: Binding<DonetickTaskForm>) -> Binding<Bool> {
        Binding(get: { !form.wrappedValue.dueTime.isEmpty }, set: { form.wrappedValue.dueTime = $0 ? "12:00" : "" })
    }

    static func date(_ form: Binding<DonetickTaskForm>) -> Binding<Date> {
        Binding(get: { formatter("yyyy-MM-dd").date(from: form.wrappedValue.dueDate) ?? .now },
                set: { form.wrappedValue.dueDate = formatter("yyyy-MM-dd").string(from: $0) })
    }

    static func time(_ form: Binding<DonetickTaskForm>) -> Binding<Date> {
        Binding(get: { formatter("HH:mm").date(from: form.wrappedValue.dueTime) ?? .now },
                set: { form.wrappedValue.dueTime = formatter("HH:mm").string(from: $0) })
    }
}

extension View {
    /// A number pad on iOS.
    func numericKeyboard() -> some View {
        #if os(iOS)
        keyboardType(.numberPad)
        #else
        self
        #endif
    }
}
