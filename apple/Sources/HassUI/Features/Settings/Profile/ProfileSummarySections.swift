import HassCore
import HassDesign
import SwiftUI

/// The Account sheet's summary: what the web's profile modal ("Your Summary", `DailyReportModal.tsx`) shows, plus who is
/// home. People at Home, then the viewer's Overdue and Upcoming Chores, then Expired Food, as list sections.
///
/// The web splits these across three tabs with badges. The sheet also holds the account, location and Sign Out, so the
/// sections stack instead (HIG Lists and tables: sections group related rows), and an empty section says so in one row.
/// A resident sees their own chores; anyone else sees People at Home and Expired Food only (the web asks "Whose
/// Summary?" and shows nothing until picked).
struct ProfileSummarySections: View {
    @Environment(EntityStore.self) private var store: EntityStore?
    @Environment(HassConnection.self) private var connection: HassConnection?
    @AppStorage(ChoresModel.viewerDefaultsKey) private var viewerUserId: String?

    var body: some View {
        if let store {
            let viewer = ChoresConfig.Resident.forUserId(viewerUserId)
            let vacation = store.entity(ChoresConfig.vacationModeEntityId).state?.state == "on"
            ProfilePeopleSection(store: store)
            if let viewer, let connection {
                ProfileChoresSections(lists: ProfileSummary.lists(for: viewer), store: store,
                                      todos: TodoStore.shared(for: connection), vacationMode: vacation)
            }
            ProfileExpiredFoodSection(store: store, vacationMode: vacation)
        }
    }
}

// MARK: - People

/// Everyone Home Assistant tracks as a person, those at home first.
private struct ProfilePeopleSection: View {
    var store: EntityStore
    @State private var ids: [String]

    var body: some View {
        let people = ProfileSummary.people(ids.compactMap { store.entity($0).state })
        if !people.isEmpty {
            Section {
                ForEach(people) { person in
                    LabeledContent {
                        Text(person.stateText)
                            .foregroundStyle(person.isHome ? HassTokens.Ink.success : HassTokens.Surface.secondaryInSheet)
                    } label: {
                        Label {
                            Text(person.name).foregroundStyle(HassTokens.Ink.primary)
                        } icon: {
                            Image(systemName: person.isHome ? "person.fill.checkmark" : "person.fill")
                                .foregroundStyle(person.isHome ? ColorFamily.occupancy.glyph : HassTokens.Surface.secondaryInSheet)
                        }
                    }
                    .frame(minHeight: HassTokens.minTarget)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("profile.person.\(person.id)")
                }
            } header: {
                SettingsSectionHeader("People at Home")
            } footer: {
                // Explicit ink: the plain footer measured 3.3:1 in the Account sheet's audit.
                Text(ProfileSummary.homeSummary(people))
                    .foregroundStyle(HassTokens.Surface.secondaryInSheet)
            }
            .accessibilityIdentifier("profile.people")
        }
    }

    /// The person ids are read once when the sheet opens: people rarely come and go, and each row then observes its
    /// own entity, so a change of state redraws only that row.
    init(store: EntityStore) {
        self.store = store
        _ids = State(initialValue: store.allValues.keys.filter { $0.hasPrefix("person.") }.sorted())
    }
}

// MARK: - Chores

/// The viewer's Overdue Chores, then Upcoming Chores (due today, then no due date).
private struct ProfileChoresSections: View {
    var lists: ProfileSummary.ResidentLists
    var store: EntityStore
    var todos: TodoStore
    var vacationMode: Bool

    var body: some View {
        let overdue = todos.controller(for: lists.overdue.entityId)
        let today = todos.controller(for: lists.dueToday.entityId)
        let noDate = todos.controller(for: lists.noDueDate.entityId)
        ProfileTodoSection(list: lists.overdue, controller: overdue, store: store,
                           emptyTitle: ProfileSummary.Empty.overdueTitle,
                           emptyText: vacationMode ? ProfileSummary.Empty.vacation : ProfileSummary.Empty.overdueDescription,
                           showsWhenEmpty: true)
        ProfileTodoSection(list: lists.dueToday, controller: today, store: store, emptyTitle: ProfileSummary.Empty.upcomingTitle,
                           emptyText: vacationMode ? ProfileSummary.Empty.vacation : ProfileSummary.Empty.upcomingDescription,
                           // Both upcoming lists empty: one row says so under the first.
                           showsWhenEmpty: !Self.hasItems(noDate, lists.noDueDate, store))
        ProfileTodoSection(list: lists.noDueDate, controller: noDate, store: store, emptyTitle: "", emptyText: "", showsWhenEmpty: false)
    }

    private static func hasItems(_ controller: TodoListController, _ list: ChoresConfig.TodoList, _ store: EntityStore) -> Bool {
        ProfileSummary.openCount(store.entity(list.entityId).state) > 0 || !controller.visibleItems(hideCompleted: true).isEmpty
    }
}

/// One todo list as list rows: its open items, or one empty row when it is meant to show empty.
private struct ProfileTodoSection: View {
    var list: ChoresConfig.TodoList
    var controller: TodoListController
    var store: EntityStore
    var emptyTitle: String
    var emptyText: String
    var showsWhenEmpty: Bool

    var body: some View {
        let entity = store.entity(list.entityId).state
        let items = controller.visibleItems(hideCompleted: true)
        let mayHaveItems = ProfileSummary.openCount(entity) > 0 || !items.isEmpty
        Group {
            if mayHaveItems || showsWhenEmpty {
                Section {
                    if controller.items == nil && mayHaveItems {
                        ArcSpinner(.compact, label: "Loading \(list.title)")
                            .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget)
                    } else if items.isEmpty {
                        ProfileEmptyRow(title: emptyTitle, text: emptyText)
                    } else {
                        let now = Date.now
                        ForEach(items) { item in
                            TodoItemRow(item: item, now: now, onToggle: { Task { await controller.toggle(item) } }, onEdit: nil)
                                .listRowInsets(EdgeInsets())
                        }
                    }
                } header: {
                    SettingsSectionHeader(list.title)
                }
                .accessibilityIdentifier("profile.section.\(list.entityId)")
            }
        }
        // Reloads when the list's count changes, as the Chores page does.
        .task(id: TodoReloadKey(entity: entity, version: 0)) { await controller.load() }
    }
}

// MARK: - Expired food

/// EverShelf's expired items, or "No Expired Food". Vacation puts the kitchen on hold, so the list is hidden.
private struct ProfileExpiredFoodSection: View {
    var store: EntityStore
    var vacationMode: Bool

    var body: some View {
        let items = ProfileSummary.expiredItems(store.entity(ProfileSummary.expiredFoodEntityId).state)
        Section {
            if vacationMode {
                ProfileEmptyRow(title: items.isEmpty ? ProfileSummary.Empty.foodTitle : "Expired Food Hidden",
                                text: ProfileSummary.Empty.vacation)
            } else if items.isEmpty {
                ProfileEmptyRow(title: ProfileSummary.Empty.foodTitle, text: ProfileSummary.Empty.foodDescription)
            } else {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.body)
                            .foregroundStyle(HassTokens.Ink.primary)
                        Text("\(item.expiredText) · \(item.locationTitle)")
                            .font(.subheadline)
                            .foregroundStyle(HassTokens.Ink.error)
                    }
                    .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
        } header: {
            SettingsSectionHeader("Expired Food")
        }
        .accessibilityIdentifier("profile.expiredFood")
    }
}

/// An empty section's one row: a title and what it means.
private struct ProfileEmptyRow: View {
    var title: String
    var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.body)
                .foregroundStyle(HassTokens.Ink.primary)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(HassTokens.Surface.secondaryInSheet)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
