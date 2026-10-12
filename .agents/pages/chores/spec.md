# Chores, Groceries and To-Do: spec

> **What:** platform-neutral behavior of the Chores tab, its five sub-pages and the admin To-Do. **Read when:** changing any todo page or sheet.

Web source `ha-sfenton-react-dash@9ac2a46`: `src/pages/DashboardViewPage.tsx` (`TodoPageContent`, `TodoSection`, `todoListVisible`, `ChoresIntro`, `ChoreQuickLink`), `src/constants/portedDashboard.ts` (`TODO_PAGES`, `CHORE_QUICK_LINKS`), `choreQuickLinkCounts.ts`, `householdResidents.ts`, `dashboardAccess.ts`, `src/components/hass/TodoListPanel.tsx`, `useDonetickTaskForm.ts`, `donetickTaskForm.ts`, `DonetickTaskFormPage.tsx`, `CreateGroceryItemSheet.tsx`, `CreateTodoItemSheet.tsx`, `EditTodoItemSheet.tsx`, `src/hooks/useTodoOptimisticStatuses.ts`, `src/components/shell/DashboardFloatingAction.tsx`.

## Pages (config: `HassCore/Config/ChoresConfig.swift`)

| Route | Title | Lists | Add | Rows edit |
|---|---|---|---|---|
| `chores` (tab) | Chores | the viewer's time-of-day lists (`*_with_unassigned`, only lists whose users include the viewer and whose entity count > 0) | Add Task (Anyone) | DoneTick form |
| `groceries` | Groceries | `todo.shopping_list` | Add Groceries | no |
| `stephens-chores`, `stephs-chores`, `unassigned-chores`, `home-improvement-chores` | per config | Past Due, Due Today, Upcoming, No Due Date | Add Task (assignee 1, 2, Anyone, 3) | DoneTick form |
| `to-do` (Settings; hidden from Steph) | To-Do | `todo.groceries`, no header; checking off runs `script.complete_admin_todo_item` | Add Task (admin, images) | rename |

- The Chores tab starts with Quick Links (Groceries, each resident's chores, Unassigned, Home Tasks) whose subtitles summarize the page's list entity counts ("2 overdue tasks · 1 task listed", "3 items"); the viewer's own link reads "Your Chores", the other resident's "{Name}'s Chores".
- A list's entity state is its open-item count: 0 hides the list before any fetch. Loaded lists with no open items hide too. When every visible list is settled and hidden, the empty state shows ("No Chores Due" / "…nice job!", "You have no chores due- nice job!" on the viewer's own page, "Enjoy vacation!" on chore pages while `input_boolean.vacation_mode` is on).
- Items load over the websocket (`todo/item/list`), sort by due (undated last), and reload when the list entity changes or a sheet saves. Completed items are hidden.
- Checking off is optimistic: the row disappears at once and returns if the call fails or nothing confirms within 15 s.
- Row: checkbox, title (battery maintenance tasks append "· 18%"), relative due ("Due in 3 days", "2 hours overdue"; overdue under a day vs longer are distinct tones), optional "Edit {title}" button. DoneTick rows are editable only when the uid starts with a task id (`42--…`).

## Sheets

- **Create / Edit Task** (DoneTick): name, assignee (Anyone, You/Stephen, You/Steph, Home Improvement), Hide While On Vacation, description, due date and time, priority (None, P1–P4), recurrence (Custom Interval adds Repeat Every 1–365 + unit; Specific Days of Week adds weekdays; editing adds Adaptive). Create → `donetick.create_task_form`; edit loads `donetick.get_task` (`return_response`, `config_entry_id` = list entity, `task_id`), saves `donetick.update_task_form` (`assignees` only when changed), deletes with `todo.remove_item` after "Delete {name}?".
- **Add Grocery Item**: `todo.add_item` on `todo.shopping_list`.
- **Add Task (admin)**: public-repo disclosure; no images → `todo.add_item`; up to four PNG/JPEG/WebP images ≤ 10 MB → multipart POST `/api/sfenton_admin_todo` with the bearer token.
- **Edit Task (admin)**: rename with `todo.update_item` `rename`; Reset restores the original.
