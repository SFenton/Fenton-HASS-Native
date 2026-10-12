import Foundation
@testable import HassCore
import Testing

struct ChoresConfigTests {
    private let stephen = ChoresConfig.Resident.stephen.haUserId
    private let steph = ChoresConfig.Resident.steph.haUserId

    @Test func residentsMapFromHomeAssistantUsers() {
        #expect(ChoresConfig.Resident.forUserId(stephen) == .stephen)
        #expect(ChoresConfig.Resident.forUserId(" \(steph.uppercased()) ") == .steph)
        #expect(ChoresConfig.Resident.forUserId("someone") == nil)
        #expect(ChoresConfig.Resident.forUserId("") == nil)
        #expect(ChoresConfig.Resident.forUserId(nil) == nil)
        #expect(ChoresConfig.Resident.stephen.name == "Stephen")
        #expect(ChoresConfig.Resident.steph.donetickAssignee == "2")
    }

    @Test func adminTodoIsHiddenOnlyFromSteph() {
        #expect(ChoresConfig.showsAdminTodo(to: .stephen))
        #expect(ChoresConfig.showsAdminTodo(to: nil))
        #expect(!ChoresConfig.showsAdminTodo(to: .steph))
    }

    @Test func pagesMatchTheWebRoutes() {
        #expect(ChoresConfig.pages.map(\.id) == ["chores", "groceries", "stephens-chores", "stephs-chores", "unassigned-chores", "home-improvement-chores", "to-do"])
        #expect(ChoresConfig.page("groceries")?.lists.first?.entityId == "todo.shopping_list")
        #expect(ChoresConfig.page("nope") == nil)
        #expect(ChoresConfig.chores.lists.count == 13)
        #expect(ChoresConfig.stephsChores.lists.map(\.entityId) == ["todo.steph_s_past_due", "todo.steph_s_due_today", "todo.steph_s_upcoming", "todo.steph_s_no_due_date"])
        #expect(ChoresConfig.homeImprovementChores.addAction == .donetickTask(defaultAssignee: "3"))
        #expect(ChoresConfig.adminTodo.editsAdminTodo)
        #expect(!ChoresConfig.groceries.editsAdminTodo)
        #expect(ChoresConfig.adminTodo.lists[0].completionScript == "script.complete_admin_todo_item")
    }

    @Test func listsShowOnlyToTheirUsersAndWhenOpen() {
        let morning = ChoresConfig.chores.lists.first { $0.entityId == "todo.stephen_s_morning_with_unassigned" }!
        let open = EntityState(entityId: morning.entityId, state: "2")
        #expect(morning.isVisible(to: stephen, openItems: open))
        #expect(!morning.isVisible(to: steph, openItems: open))
        #expect(!morning.isVisible(to: nil, openItems: open))
        #expect(!morning.isVisible(to: stephen, openItems: EntityState(entityId: morning.entityId, state: "0")))
        #expect(!morning.isVisible(to: stephen, openItems: nil))
        let grocery = ChoresConfig.groceries.lists[0]
        #expect(grocery.isVisible(to: nil, openItems: nil))
    }

    @Test func emptyDescriptionsPersonalizeAndYieldToVacation() {
        let page = ChoresConfig.stephensChores
        #expect(page.emptyDescription(viewer: .steph, vacationModeOn: false) == "Stephen has no chores due- nice job!")
        #expect(page.emptyDescription(viewer: .stephen, vacationModeOn: false) == "You have no chores due- nice job!")
        #expect(page.emptyDescription(viewer: .stephen, vacationModeOn: true) == "Enjoy vacation!")
        #expect(ChoresConfig.groceries.emptyDescription(viewer: nil, vacationModeOn: true) == "Add some groceries to see them appear.")
    }

    @Test func quickLinksPersonalizeTitles() {
        let links = ChoresConfig.quickLinks
        #expect(links.map(\.id) == ["groceries", "stephens-chores", "stephs-chores", "unassigned-chores", "home-improvement-chores"])
        #expect(links[1].title(viewer: .stephen) == "Your Chores")
        #expect(links[1].title(viewer: .steph) == "Stephen's Chores")
        #expect(links[1].title(viewer: nil) == "Stephen's Tasks")
        #expect(links[3].title(viewer: .stephen) == "Unassigned Tasks")
        #expect(links[0] == links[0] && links[0] != links[1])
        #expect(Set(links).count == links.count)
    }

    @Test func countsSumIntoBuckets() {
        let states: [String: String] = ["todo.stephen_s_past_due": "2", "todo.stephen_s_due_today": "1", "todo.stephen_s_upcoming": "3",
                                        "todo.stephen_s_no_due_date": "1", "todo.shopping_list": "unavailable"]
        let lookup: (String) -> EntityState? = { id in states[id].map { EntityState(entityId: id, state: $0) } }
        #expect(ChoresConfig.counts(for: ChoresConfig.stephensChores, lookup) == .init(overdue: 2, upcoming: 4, noDueDate: 1, total: 7))
        #expect(ChoresConfig.counts(for: ChoresConfig.groceries, lookup) == .init())
        #expect(ChoresConfig.quickLinks[1].subtitle(lookup) == "2 overdue tasks · 1 task listed")
        #expect(ChoresConfig.quickLinks[0].subtitle(lookup) == "No groceries listed")
    }

    @Test func subtitlesFollowTheWebWording() {
        #expect(ChoresConfig.choreSubtitle(.init(overdue: 1)) == "1 overdue task")
        #expect(ChoresConfig.choreSubtitle(.init(upcoming: 3)) == "3 upcoming tasks")
        #expect(ChoresConfig.choreSubtitle(.init(upcoming: 1, noDueDate: 2)) == "1 upcoming task · 2 tasks listed")
        #expect(ChoresConfig.choreSubtitle(.init(noDueDate: 1)) == "1 task listed")
        #expect(ChoresConfig.choreSubtitle(.init()) == "No tasks listed")
        #expect(ChoresConfig.grocerySubtitle(1) == "1 item")
        #expect(ChoresConfig.grocerySubtitle(4) == "4 items")
        #expect(ChoresConfig.grocerySubtitle(0) == "No groceries listed")
    }
}
