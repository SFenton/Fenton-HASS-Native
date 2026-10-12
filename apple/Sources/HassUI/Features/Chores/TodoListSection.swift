import HassCore
import HassDesign
import SwiftUI

/// One todo list: an optional header, any error, and its open items as checkable rows
/// (web `TodoSection` + `TodoListPanel`). DoneTick pages lay rows out in the dynamic grid; other lists stack.
struct TodoListSection: View {
    enum Layout { case list, grid }

    var list: ChoresConfig.TodoList
    var controller: TodoListController
    var showsHeader = true
    var layout: Layout = .list
    /// The row's edit action, or `nil` when the row can't be edited.
    var editor: (TodoItem) -> (() -> Void)? = { _ in nil }

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
            if showsHeader {
                Text(list.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(HassTokens.Ink.primary)
                    .accessibilityAddTraits(.isHeader)
            }
            if let error = controller.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(HassTokens.Ink.primary)
                    .symbolRenderingMode(.multicolor)
                    .accessibilityIdentifier("todo.error.\(list.entityId)")
            }
            let items = controller.visibleItems(hideCompleted: list.hideCompleted)
            if controller.items == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget)
                    .accessibilityLabel("Loading \(list.title)")
            } else if layout == .grid {
                DynamicGridLayout(minCellWidth: 280, maxColumns: 3) {
                    ForEach(items) { row($0) }
                }
            } else {
                VStack(spacing: HassTokens.Spacing.s) {
                    ForEach(items) { row($0) }
                }
            }
        }
        .accessibilityIdentifier("todo.section.\(list.entityId)")
    }

    private func row(_ item: TodoItem) -> some View {
        TodoItemRow(
            item: item,
            onToggle: { Task { await controller.toggle(item, completionScript: list.completionScript) } },
            onEdit: editor(item)
        )
    }
}

/// A checkable task row with its due label and an optional edit button (web `CheckboxRow` in `TodoListPanel`).
struct TodoItemRow: View {
    var item: TodoItem
    var now: Date = .now
    var onToggle: () -> Void
    var onEdit: (() -> Void)?

    var body: some View {
        let title = item.displayTitle
        let due = item.dueLabel(now: now)
        HStack(alignment: .center, spacing: HassTokens.Spacing.s) {
            Button(action: onToggle) {
                HStack(alignment: .firstTextBaseline, spacing: HassTokens.Spacing.m) {
                    Image(systemName: item.status == .completed ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(item.status == .completed ? AnyShapeStyle(.tint) : AnyShapeStyle(HassTokens.Ink.secondary))
                    VStack(alignment: .leading, spacing: HassTokens.Spacing.xs) {
                        Text(title)
                            .font(.body.weight(.medium))
                            .foregroundStyle(HassTokens.Ink.primary)
                            .strikethrough(item.status == .completed)
                            .fixedSize(horizontal: false, vertical: true)
                        if let due {
                            DueLabel(text: due.text, tone: due.tone)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(Self.accessibilityValue(completed: item.status == .completed, due: due?.text))
            .accessibilityAddTraits(.isToggle)
            .accessibilityHint(item.status == .completed ? "Marks the task not done." : "Marks the task done.")
            .accessibilityIdentifier("todo.item.\(item.identity)")

            if let onEdit {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                        .frame(minWidth: HassTokens.minTarget, minHeight: HassTokens.minTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit \(title)")
                .accessibilityIdentifier("todo.edit.\(item.identity)")
            }
        }
        .padding(.leading, HassTokens.Spacing.m)
        .padding(.trailing, onEdit == nil ? HassTokens.Spacing.m : HassTokens.Spacing.xs)
        .padding(.vertical, HassTokens.Spacing.xs)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: HassTokens.Radius.chip, style: .continuous))
    }

    /// "Not done, Due in 3 days" or "Done".
    static func accessibilityValue(completed: Bool, due: String?) -> String {
        if completed { return "Done" }
        return ["Not done", due].compactMap { $0 }.joined(separator: ", ")
    }
}

/// "Due in 3 days" in secondary ink, or an overdue span with a warning symbol (orange under a day,
/// red beyond). Text stays in label ink so it keeps 4.5:1 on the material; the symbol carries the color.
struct DueLabel: View {
    var text: String
    var tone: TodoItem.DueTone

    var body: some View {
        HStack(spacing: HassTokens.Spacing.xs) {
            switch tone {
            case .future:
                EmptyView()
            case .overdueHours:
                Image(systemName: "clock.badge.exclamationmark.fill").foregroundStyle(.orange)
            case .overdueLong:
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
            }
            Text(text)
                .foregroundStyle(tone == .future ? HassTokens.Ink.secondary : HassTokens.Ink.primary)
                .fontWeight(tone == .future ? .regular : .semibold)
        }
        .font(.footnote)
    }
}
