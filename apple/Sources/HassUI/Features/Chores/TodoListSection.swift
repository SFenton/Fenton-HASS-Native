import HassCore
import HassDesign
import SwiftUI

/// One todo list: an optional header, any error, and its open items as checkable rows on one module
/// (web `TodoSection` + `TodoListPanel`; direction G mockups n5: an inset list on the wallpaper, as in Reminders).
struct TodoListSection: View {
    var list: ChoresConfig.TodoList
    var controller: TodoListController
    var showsHeader = true
    /// The edit button's glyph: `info.circle` for a DoneTick task, `pencil` for an admin to-do (mockups n5).
    var editSymbol = "info.circle"
    /// The row's edit action, or `nil` when the row can't be edited.
    var editor: (TodoItem) -> (() -> Void)? = { _ in nil }

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
            if showsHeader {
                PageSectionHeader(list.title)
            }
            if let error = controller.error {
                InlineAlert(error)
                    .accessibilityIdentifier("todo.error.\(list.entityId)")
            }
            let items = controller.visibleItems(hideCompleted: list.hideCompleted)
            if controller.items == nil {
                ArcSpinner(.compact, label: "Loading \(list.title)")
                    .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget)
            } else if !items.isEmpty {
                let now = Date.now
                // Overdue spans are orange and red text, which needs the dense module over the lit windows
                // (direction G, Layers).
                ModuleList(TodoListSection.hasLateItem(items, now: now) ? .dense : .thin) {
                    ForEach(items) { item in
                        row(item, now: now)
                    }
                }
            }
        }
        // A container keeps each row's own identifiers: on a plain stack the section's identifier overwrote
        // them once the rows lost their material card (2026-10-13).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("todo.section.\(list.entityId)")
    }

    private func row(_ item: TodoItem, now: Date) -> some View {
        TodoItemRow(
            item: item,
            now: now,
            editSymbol: editSymbol,
            onToggle: { Task { await controller.toggle(item, completionScript: list.completionScript) } },
            onEdit: editor(item)
        )
    }

    /// Whether any open row shows an overdue span, which is drawn in orange or red.
    static func hasLateItem(_ items: [TodoItem], now: Date) -> Bool {
        items.contains { item in
            guard item.status != .completed, let tone = item.dueLabel(now: now)?.tone else { return false }
            return tone != .future
        }
    }
}

/// A checkable task row with its due label and an optional edit button (web `CheckboxRow` in `TodoListPanel`; direction
/// G mockups n5: a 24 pt circle, a 17 pt title, a 15 pt due line, and a trailing info or pencil glyph). The title starts
/// 16 + 24 + 14 pt in, where ``ModuleList`` insets its hairlines, so it keeps its own toggle and edit layout over
/// ``ModuleRow``'s.
struct TodoItemRow: View {
    var item: TodoItem
    var now: Date = .now
    var editSymbol = "info.circle"
    var onToggle: () -> Void
    var onEdit: (() -> Void)?

    var body: some View {
        let title = item.displayTitle
        let done = item.status == .completed
        let due = done ? nil : item.dueLabel(now: now)
        HStack(alignment: .center, spacing: 0) {
            Button(action: onToggle) {
                // The symbol takes the title's font and baseline, so it centers on the first line however
                // the title wraps (the Label idiom; HIG Typography, SF Symbols "Alignment").
                HStack(alignment: .firstTextBaseline, spacing: ModuleRowMetrics.gap) {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                        .font(.body)
                        .imageScale(.large)
                        .foregroundStyle(done ? AnyShapeStyle(.green) : AnyShapeStyle(HassTokens.Surface.secondaryOnModule))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.body)
                            .foregroundStyle(done ? HassTokens.Surface.secondaryOnModule : HassTokens.Ink.primary)
                            .strikethrough(done)
                            .fixedSize(horizontal: false, vertical: true)
                        if let due {
                            DueLabel(text: due.text, tone: due.tone)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, HassTokens.Spacing.l)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity, minHeight: due == nil ? 52 : 60, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(Self.accessibilityValue(completed: done, due: due?.text))
            .accessibilityAddTraits(.isToggle)
            .accessibilityHint(done ? "Marks the task not done." : "Marks the task done.")
            .accessibilityIdentifier("todo.item.\(item.identity)")

            if let onEdit {
                Button(action: onEdit) {
                    Image(systemName: editSymbol)
                        .font(.title3)
                        .foregroundStyle(HassTokens.Surface.secondaryOnModule)
                        .frame(minWidth: HassTokens.minTarget, minHeight: HassTokens.minTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, HassTokens.Spacing.xs)
                .accessibilityLabel("Edit \(title)")
                .accessibilityIdentifier("todo.edit.\(item.identity)")
            } else {
                Spacer().frame(width: HassTokens.Spacing.l)
            }
        }
    }

    /// "Not done, Due in 3 days" or "Done".
    static func accessibilityValue(completed: Bool, due: String?) -> String {
        if completed { return "Done" }
        return ["Not done", due].compactMap { $0 }.joined(separator: ", ")
    }
}

/// "Due in 3 days" after a calendar glyph in secondary ink, or an overdue span after a clock: orange under a day, red
/// beyond (direction G, Colour: `#FFB340` soon, `#FF6961` overdue). The list's module turns dense under red and orange
/// text so it keeps 4.5:1 over the wallpaper.
struct DueLabel: View {
    var text: String
    var tone: TodoItem.DueTone

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: HassTokens.Spacing.xs) {
            Image(systemName: tone == .future ? "calendar" : "clock")
                .imageScale(.small)
                .accessibilityHidden(true)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.subheadline)
        .monospacedDigit()
        .foregroundStyle(Self.color(tone))
    }

    /// The text and glyph colour for a tone.
    static func color(_ tone: TodoItem.DueTone) -> Color {
        switch tone {
        case .future: HassTokens.Surface.secondaryOnModule
        case .overdueHours: HassTokens.Ink.warning
        case .overdueLong: HassTokens.Ink.error
        }
    }
}
