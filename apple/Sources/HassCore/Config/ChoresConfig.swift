import Foundation

/// Chores, Groceries and To-Do pages: the web's `TODO_PAGES`, `CHORE_QUICK_LINKS` and household residents
/// (`ha-sfenton-react-dash:src/constants/portedDashboard.ts`, `householdResidents.ts`, `choreQuickLinkCounts.ts`).
public enum ChoresConfig {
    // MARK: - Residents

    /// A household member, keyed to their Home Assistant user.
    public enum Resident: String, CaseIterable, Sendable {
        case stephen, steph

        /// Display name.
        public var name: String {
            switch self {
            case .stephen: "Stephen"
            case .steph: "Steph"
            }
        }

        /// Home Assistant user id (`HOUSEHOLD_RESIDENTS[...].haUserId`).
        public var haUserId: String {
            switch self {
            case .stephen: "64089b5683944c39b4f944c8f76830b0"
            case .steph: "43cb71bbd1cb4860b2a7de4c829020f0"
            }
        }

        /// DoneTick user id used as the task form's assignee value.
        public var donetickAssignee: String {
            switch self {
            case .stephen: "1"
            case .steph: "2"
            }
        }

        /// The resident signed in as `userId`, if any.
        public static func forUserId(_ userId: String?) -> Resident? {
            guard let userId = userId?.trimmingCharacters(in: .whitespaces).lowercased(), !userId.isEmpty else { return nil }
            return allCases.first { $0.haUserId == userId }
        }
    }

    // MARK: - Lists and pages

    /// Which quick-link subtitle bucket a list counts toward.
    public enum CountBucket: Sendable { case overdue, upcoming, noDueDate }

    /// One Home Assistant `todo` list shown as a section.
    public struct TodoList: Hashable, Sendable, Identifiable {
        public var title: String
        public var entityId: String
        /// Script run instead of `todo.update_item` when an item is checked off (admin To-Do).
        public var completionScript: String?
        public var countBucket: CountBucket?
        /// Completed items are hidden (the web default).
        public var hideCompleted = true
        /// The list is skipped while its entity reports no open items.
        public var hideWhenNoOpenItems = false
        /// Only these Home Assistant users see the list; empty means everyone.
        public var userIds: [String] = []

        public var id: String { entityId }

        /// Whether the signed-in `userId` sees this list, given the list entity's open-item count (web `todoListVisible`).
        public func isVisible(to userId: String?, openItems: EntityState?) -> Bool {
            if !userIds.isEmpty {
                guard let userId, userIds.contains(userId) else { return false }
            }
            guard hideWhenNoOpenItems else { return true }
            return (openItems?.numericState ?? 0) > 0
        }
    }

    /// What the page's Add button creates.
    public enum AddAction: Hashable, Sendable {
        /// A DoneTick task, preassigned to this assignee value ("" is Anyone).
        case donetickTask(defaultAssignee: String)
        /// A grocery item on this list.
        case groceryItem(entityId: String)
        /// An admin to-do (synced to GitHub; may carry images).
        case adminTodo(entityId: String)
    }

    /// A page of todo lists (web `TodoPageConfig`).
    public struct Page: Hashable, Sendable, Identifiable {
        /// Route path, e.g. `stephens-chores`.
        public var id: String
        public var title: String
        public var lists: [TodoList]
        public var emptyTitle: String
        public var emptyDescription: String
        /// Shows the vacation message instead of "nice job" while Vacation Mode is on.
        public var hiddenByVacation = false
        public var hideListHeaders = false
        /// Tasks come from DoneTick: rows are editable through the task form and lay out as a grid.
        public var isDonetick = false
        /// The resident whose chores these are (personalized empty state).
        public var resident: Resident?
        public var addAction: AddAction

        /// Whether rows can be renamed (the admin To-Do only).
        public var editsAdminTodo: Bool {
            if case .adminTodo = addAction { return true }
            return false
        }

        /// The empty-state description for `viewer`: personal when it is their own page, vacation copy when hidden.
        public func emptyDescription(viewer: Resident?, vacationModeOn: Bool) -> String {
            if hiddenByVacation && vacationModeOn { return ChoresConfig.vacationEmptyDescription }
            if let resident, resident == viewer { return "You have no chores due- nice job!" }
            return emptyDescription
        }
    }

    // MARK: - Entities

    /// `input_boolean.vacation_mode`.
    public static let vacationModeEntityId = "input_boolean.vacation_mode"
    /// Web `pageVacation.empty.description`.
    public static let vacationEmptyDescription = "Enjoy vacation!"
    /// The admin To-Do list (web `ADMIN_TODO_ENTITY_ID`).
    public static let adminTodoEntityId = "todo.groceries"
    /// Grocery list.
    public static let groceryEntityId = "todo.shopping_list"
    /// Endpoint for admin to-dos with images (multipart POST, `CreateTodoItemSheet.tsx`).
    public static let adminTodoUploadPath = "/api/sfenton_admin_todo"

    // MARK: - Pages

    private static func donetickLists(_ prefix: String) -> [TodoList] {
        [
            TodoList(title: "Past Due", entityId: "todo.\(prefix)_past_due", countBucket: .overdue),
            TodoList(title: "Due Today", entityId: "todo.\(prefix)_due_today", countBucket: .upcoming),
            TodoList(title: "Upcoming", entityId: "todo.\(prefix)_upcoming", countBucket: .upcoming),
            TodoList(title: "No Due Date", entityId: "todo.\(prefix)_no_due_date", countBucket: .noDueDate),
        ]
    }

    private static func choresTabLists() -> [TodoList] {
        func list(_ title: String, _ entity: String, _ resident: Resident) -> TodoList {
            TodoList(title: title, entityId: "todo.\(entity)_with_unassigned", hideWhenNoOpenItems: true, userIds: [resident.haUserId])
        }
        return [
            list("Past Due", "stephen_s_past_due", .stephen),
            list("Evening Tasks", "stephen_s_evening", .stephen),
            list("Afternoon Tasks", "stephen_s_afternoon", .stephen),
            list("Morning Tasks", "stephen_s_morning", .stephen),
            list("Due Any Time Today", "stephen_s_all_day", .stephen),
            list("No Due Date", "stephen_s_no_due_date", .stephen),
            list("Evening Tasks", "steph_s_evening", .steph),
            list("Afternoon Tasks", "steph_s_afternoon", .steph),
            list("Morning Tasks", "steph_s_morning", .steph),
            list("Due Any Time Today", "steph_s_all_day", .steph),
            list("No Due Date", "steph_s_no_due_date", .steph),
            list("Upcoming", "stephen_s_upcoming_today_by_time_and_future", .stephen),
            list("Upcoming", "steph_s_upcoming_today_by_time_and_future", .steph),
        ]
    }

    /// The Chores tab's own lists: the signed-in resident's chores grouped by time of day.
    public static let chores = Page(
        id: "chores", title: "Chores", lists: choresTabLists(),
        emptyTitle: "No Chores Due", emptyDescription: "You have no chores due- nice job!",
        hiddenByVacation: true, isDonetick: true, addAction: .donetickTask(defaultAssignee: "")
    )

    /// Groceries.
    public static let groceries = Page(
        id: "groceries", title: "Groceries",
        lists: [TodoList(title: "Grocery List", entityId: groceryEntityId)],
        emptyTitle: "No Groceries Listed", emptyDescription: "Add some groceries to see them appear.",
        addAction: .groceryItem(entityId: groceryEntityId)
    )

    /// Stephen's chores.
    public static let stephensChores = Page(
        id: "stephens-chores", title: "Stephen's Chores", lists: donetickLists("stephen_s"),
        emptyTitle: "No Chores Due", emptyDescription: "Stephen has no chores due- nice job!",
        hiddenByVacation: true, isDonetick: true, resident: .stephen,
        addAction: .donetickTask(defaultAssignee: Resident.stephen.donetickAssignee)
    )

    /// Steph's chores.
    public static let stephsChores = Page(
        id: "stephs-chores", title: "Steph's Chores", lists: donetickLists("steph_s"),
        emptyTitle: "No Chores Due", emptyDescription: "Steph has no chores due- nice job!",
        hiddenByVacation: true, isDonetick: true, resident: .steph,
        addAction: .donetickTask(defaultAssignee: Resident.steph.donetickAssignee)
    )

    /// Chores nobody is assigned to.
    public static let unassignedChores = Page(
        id: "unassigned-chores", title: "Unassigned Chores", lists: donetickLists("unassigned"),
        emptyTitle: "No Chores Due", emptyDescription: "There are no unassigned chores due- nice job!",
        hiddenByVacation: true, isDonetick: true, addAction: .donetickTask(defaultAssignee: "")
    )

    /// Home improvement tasks.
    public static let homeImprovementChores = Page(
        id: "home-improvement-chores", title: "Home Improvement Tasks", lists: donetickLists("home_improvement_s"),
        emptyTitle: "No Tasks Due", emptyDescription: "There are no home improvement tasks due- nice job!",
        hiddenByVacation: true, isDonetick: true, addAction: .donetickTask(defaultAssignee: "3")
    )

    /// The admin To-Do page (Settings; Stephen only).
    public static let adminTodo = Page(
        id: "to-do", title: "To-Do",
        lists: [TodoList(title: "Admin To-Do", entityId: adminTodoEntityId, completionScript: "script.complete_admin_todo_item")],
        emptyTitle: "No To-Do Tasks", emptyDescription: "Use Add Task to create an admin to-do.",
        hideListHeaders: true, addAction: .adminTodo(entityId: adminTodoEntityId)
    )

    /// Every page, keyed by route path.
    public static let pages: [Page] = [chores, groceries, stephensChores, stephsChores, unassignedChores, homeImprovementChores, adminTodo]

    /// The page for a route path.
    public static func page(_ id: String) -> Page? { pages.first { $0.id == id } }

    /// The admin To-Do is hidden from Steph (web `isDashboardPathVisibleToResident`).
    public static func showsAdminTodo(to viewer: Resident?) -> Bool { viewer != .steph }

    // MARK: - Quick links

    /// A Chores tab quick link to a sub-page.
    public struct QuickLink: Hashable, Sendable, Identifiable {
        public var title: String
        public var page: Page
        /// sRGB 0...255 (web card colors).
        public var color: (red: Double, green: Double, blue: Double)
        public var countsGroceries = false
        public var resident: Resident?

        public var id: String { page.id }

        /// "Your Tasks" on the viewer's own link, the web's personalized title.
        public func title(viewer: Resident?) -> String {
            guard let resident, let viewer else { return title }
            return resident == viewer ? "Your Chores" : "\(resident.name)'s Chores"
        }

        /// The subtitle from the page's list counts.
        public func subtitle(_ entity: (String) -> EntityState?) -> String {
            let counts = ChoresConfig.counts(for: page, entity)
            return countsGroceries ? ChoresConfig.grocerySubtitle(counts.total) : ChoresConfig.choreSubtitle(counts)
        }

        public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
        public func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    /// The Chores tab quick links, in web order.
    public static let quickLinks: [QuickLink] = [
        QuickLink(title: "Groceries", page: groceries, color: (155, 67, 72), countsGroceries: true),
        QuickLink(title: "Stephen's Tasks", page: stephensChores, color: (0, 96, 120), resident: .stephen),
        QuickLink(title: "Steph's Tasks", page: stephsChores, color: (212, 108, 0), resident: .steph),
        QuickLink(title: "Unassigned Tasks", page: unassignedChores, color: (81, 58, 126)),
        QuickLink(title: "Home Tasks", page: homeImprovementChores, color: (64, 143, 154)),
    ]

    // MARK: - Counts

    /// Open-item counts behind a quick-link subtitle.
    public struct Counts: Equatable, Sendable {
        public var overdue = 0
        public var upcoming = 0
        public var noDueDate = 0
        public var total = 0

        public init(overdue: Int = 0, upcoming: Int = 0, noDueDate: Int = 0, total: Int = 0) {
            self.overdue = overdue
            self.upcoming = upcoming
            self.noDueDate = noDueDate
            self.total = total
        }
    }

    /// Sums each list entity's open-item count into its bucket (web `choreQuickLinkCounts`).
    public static func counts(for page: Page, _ entity: (String) -> EntityState?) -> Counts {
        page.lists.reduce(into: Counts()) { counts, list in
            let value = entity(list.entityId)?.numericState ?? 0
            let count = value.isFinite && value > 0 ? Int(value) : 0
            switch list.countBucket {
            case .overdue: counts.overdue += count
            case .upcoming: counts.upcoming += count
            case .noDueDate: counts.noDueDate += count
            case nil: break
            }
            counts.total += count
        }
    }

    private static func pluralized(_ count: Int, _ singular: String, _ plural: String) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }

    /// "2 overdue tasks · 1 task listed": overdue outranks upcoming; undated tasks are a second clause.
    public static func choreSubtitle(_ counts: Counts) -> String {
        let dated = counts.overdue > 0
            ? pluralized(counts.overdue, "overdue task", "overdue tasks")
            : counts.upcoming > 0 ? pluralized(counts.upcoming, "upcoming task", "upcoming tasks") : ""
        let undated = counts.noDueDate > 0 ? pluralized(counts.noDueDate, "task listed", "tasks listed") : ""
        if !dated.isEmpty && !undated.isEmpty { return "\(dated) · \(undated)" }
        return [dated, undated].first { !$0.isEmpty } ?? "No tasks listed"
    }

    /// "3 items" or "No groceries listed".
    public static func grocerySubtitle(_ count: Int) -> String {
        count > 0 ? pluralized(count, "item", "items") : "No groceries listed"
    }
}
