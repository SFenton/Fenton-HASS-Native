import HassCore
import HassDesign
import SwiftUI

/// One todo list as a `List` section: an optional header row, any error, and its open items as checkable rows on one
/// module (web `TodoSection` + `TodoListPanel`; direction G mockups n5: an inset list on the wallpaper, as in Reminders).
///
/// The page is a real `List` because swipe actions need one before iOS 27 (owner, 2026-10-16; the Inventory pages do the
/// same). Each row draws its share of the module with ``ModuleRowBackground``, so the rows read as one card.
struct TodoListSection: View {
    var list: ChoresConfig.TodoList
    var controller: TodoListController
    var showsHeader = true
    /// The first section on its page, which sits closer to the top than one that follows another.
    var leadsPage = false
    /// The row's edit action, or `nil` when the row can't be edited.
    var editor: (TodoItem) -> (() -> Void)? = { _ in nil }
    /// Asks the page to confirm and delete the row's task, or `nil` when the page can't delete tasks.
    var deleter: ((TodoItem) -> Void)?

    var body: some View {
        let items = controller.visibleItems(hideCompleted: list.hideCompleted)
        Section {
            if showsHeader {
                PageSectionHeader(list.title)
                    .modifier(TodoPlainRow(top: leadsPage ? HassTokens.Spacing.m : HassTokens.Spacing.xl, bottom: HassTokens.Spacing.s))
            }
            if let error = controller.error {
                InlineAlert(error)
                    .accessibilityIdentifier("todo.error.\(list.entityId)")
                    .modifier(TodoPlainRow(top: 0, bottom: HassTokens.Spacing.s))
            }
            if controller.items == nil {
                ArcSpinner(.compact, label: "Loading \(list.title)")
                    .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget)
                    .modifier(TodoPlainRow(top: 0, bottom: 0))
            } else if !items.isEmpty {
                let now = Date.now
                // Overdue spans are orange and red text, which needs the dense module over the lit windows
                // (direction G, Layers).
                let density: ModuleDensity = TodoListSection.hasLateItem(items, now: now) ? .dense : .thin
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    row(item, now: now)
                        .moduleRowSeparator(isFirst: index == 0)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(ModuleRowBackground(density, isFirst: index == 0, isLast: index == items.count - 1))
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            swipeButtons(for: item, edge: .leading)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            swipeButtons(for: item, edge: .trailing)
                        }
                        .contextMenu { menu(for: item) }
                }
            }
        }
        .sectionSpacingNone()
    }

    // MARK: Rows

    private func row(_ item: TodoItem, now: Date) -> some View {
        TodoItemRow(
            item: item,
            now: now,
            onToggle: { toggle(item) },
            onEdit: editor(item),
            onDelete: deleter.map { ask in { ask(item) } }
        )
    }

    private func toggle(_ item: TodoItem) {
        Task { await controller.toggle(item, completionScript: list.completionScript) }
    }

    /// The actions a row offers: one source for the swipes, the context menu and VoiceOver.
    private func actions(for item: TodoItem) -> TodoRowActions {
        TodoRowActions(item: item, canEdit: editor(item) != nil, canDelete: deleter != nil)
    }

    private func perform(_ action: TodoRowActions.Action, on item: TodoItem) {
        switch action {
        case .complete, .reopen: toggle(item)
        case .edit: editor(item)?()
        case .delete: deleter?(item)
        }
    }

    // MARK: Swipe and context menu

    /// Swipe buttons for an edge: Complete leads in green; Delete (red, outermost) and Edit (blue) trail. The fills are
    /// the app's darker ones so the white label keeps 4.5:1.
    @ViewBuilder
    private func swipeButtons(for item: TodoItem, edge: HorizontalEdge) -> some View {
        let actions = actions(for: item)
        ForEach(edge == .leading ? actions.leading : actions.trailing, id: \.self) { action in
            Button(action.title, systemImage: action.symbol, role: action == .delete ? .destructive : nil) {
                perform(action, on: item)
            }
            .tint(TodoListSection.swipeTint(action))
            .accessibilityIdentifier("todo.swipe.\(action.rawValue).\(item.identity)")
        }
    }

    @ViewBuilder
    private func menu(for item: TodoItem) -> some View {
        ForEach(actions(for: item).all, id: \.self) { action in
            Button(action.title, systemImage: action.symbol, role: action == .delete ? .destructive : nil) {
                perform(action, on: item)
            }
        }
    }

    /// The fill behind a swipe button.
    static func swipeTint(_ action: TodoRowActions.Action) -> Color {
        switch action {
        case .complete, .reopen: ColorFamily.occupancy.fill ?? .green
        case .edit: HassTokens.Ink.actionFill
        case .delete: HassTokens.Ink.badge
        }
    }

    /// Whether any open row shows an overdue span, which is drawn in orange or red.
    static func hasLateItem(_ items: [TodoItem], now: Date) -> Bool {
        items.contains { item in
            guard item.status != .completed, let tone = item.dueLabel(now: now)?.tone else { return false }
            return tone != .future
        }
    }
}

/// A list row that is not part of the module: a header, an error, a spinner, the quick links or the empty state. It
/// draws no card and no separator, and keeps no system insets, so it lines up with the module's edges.
struct TodoPlainRow: ViewModifier {
    var top: CGFloat
    var bottom: CGFloat
    @Environment(\.todoRowMetrics) private var metrics

    func body(content: Content) -> some View {
        content
            // How wide the list's margin leaves a row, for the quick links header to line up with (``AlignedToListMargins``). A
            // width does not change as the list scrolls, where a position did, on every frame.
            .onGeometryChange(for: CGFloat.self) { $0.size.width.rounded() } action: { metrics?.report(rowWidth: $0) }
            .listRowInsets(EdgeInsets(top: top, leading: 0, bottom: bottom, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

/// A checkable task row with its due label and an optional edit button (web `CheckboxRow` in `TodoListPanel`; direction
/// G mockups n5: a check circle the size of the title, a 17 pt title, a 15 pt due line, and a trailing edit glyph). The
/// title starts 16 + 24 + 14 pt in, where the module's hairlines inset, so it keeps its own toggle and edit layout over
/// ``ModuleRow``'s.
///
/// Owner, 2026-10-16: the check circle is the size of the text. It takes the title's font at the symbol's default scale,
/// so it follows Dynamic Type with the title, inside a 24 pt `@ScaledMetric` column. The whole row is the toggle's hit
/// area, 52 pt tall or more.
struct TodoItemRow: View {
    var item: TodoItem
    var now: Date = .now
    var onToggle: () -> Void
    var onEdit: (() -> Void)?
    /// Asks to delete the task (a VoiceOver custom action; the swipe and the context menu live on the list row).
    var onDelete: (() -> Void)?

    /// The check column's width, scaled with the title so the title stays on the module's hairline inset.
    @ScaledMetric(relativeTo: .body) private var checkColumn: CGFloat = ModuleRowMetrics.glyphWidth
    /// On the wallpaper the secondary ink is fixed light; in a sheet (the Summary's chore tabs) it follows the sheet.
    @Environment(\.tileSurface) private var surface

    /// The glyph for an open and a done task.
    static func checkSymbol(done: Bool) -> String { done ? "checkmark.circle.fill" : "circle" }

    /// The edit button's glyph (owner, 2026-10-16: not the info circle).
    static let editSymbol = "square.and.pencil"

    var body: some View {
        let title = item.displayTitle
        let done = item.status == .completed
        let due = done ? nil : item.dueLabel(now: now)
        HStack(alignment: .center, spacing: 0) {
            Button(action: onToggle) {
                // The symbol takes the title's font and baseline, so it centers on the first line however
                // the title wraps (the Label idiom; HIG Typography, SF Symbols "Alignment").
                HStack(alignment: .firstTextBaseline, spacing: ModuleRowMetrics.gap) {
                    Image(systemName: Self.checkSymbol(done: done))
                        .font(.body)
                        .foregroundStyle(done ? AnyShapeStyle(.green) : AnyShapeStyle(surface.secondaryInk))
                        .frame(width: checkColumn)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.body)
                            .foregroundStyle(done ? surface.secondaryInk : HassTokens.Ink.primary)
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
            // The trailing swipe's actions, for VoiceOver.
            .accessibilityActions {
                if let onEdit { Button("Edit", action: onEdit) }
                if let onDelete { Button("Delete", action: onDelete) }
            }

            if let onEdit {
                Button(action: onEdit) {
                    Image(systemName: Self.editSymbol)
                        .font(.title3)
                        .foregroundStyle(surface.secondaryInk)
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
    @Environment(\.tileSurface) private var surface

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
        .foregroundStyle(Self.color(tone, surface: surface))
    }

    /// The text and glyph colour for a tone on a surface (a sheet's secondary ink follows its appearance).
    static func color(_ tone: TodoItem.DueTone, surface: TileSurface = .page) -> Color {
        switch tone {
        case .future: surface.secondaryInk
        case .overdueHours: HassTokens.Ink.warning
        case .overdueLong: HassTokens.Ink.error
        }
    }
}

extension View {
    /// No gap between a list's sections on iOS: the section headers carry the spacing. (`listSectionSpacing` is
    /// unavailable on macOS, where the hosted tests run.)
    func sectionSpacingNone() -> some View {
        #if os(iOS)
        listSectionSpacing(0)
        #else
        self
        #endif
    }
}
