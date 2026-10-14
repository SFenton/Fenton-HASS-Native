# Chores, Groceries and To-Do (iPhone and iPad)

> **What:** native structure and departures for the todo pages. **Read when:** changing `HassUI/Features/Chores` or `HassCore/Todo`.

- `ChoresScreen` (tab) and `AdminTodoScreen` (Settings row, hidden from Steph by the cached viewer id) host a `ChoresModel` (service, shared `TodoStore`, viewer id cached in `UserDefaults` `chores.viewerUserId` and refreshed from `auth/current_user`). Sub-pages push with `navigationDestination(for: ChoresConfig.Page.self)`, which hands the `ChoresModel` on explicitly: a pushed page's environment comes from the section's `NavigationStack`, above `ChoresModelHost`, and without it every quick link crashed (2026-10-13).
- `TodoStore.shared(for:)` keeps one `TodoListController` per list for the connection, so lists keep their items across pages, and `TodoItemsCache` (Application Support `TodoItems.json`, file-protected, per server) shows the last items on a cold launch before the first fetch. Sign-out clears it and the viewer id.
- Every visible list loads from a zero-size background view, drawn or not, so a hidden list reappears when its entity count rises.
- Add is the shared floating action bar ([floating-actions](../../patterns/floating-actions.md)); HIG: Buttons. Sheets are `NavigationStack` + `Form` with Cancel / confirm in the bar (HIG: Sheets); the DoneTick form opens at the large detent, the one-field sheets at medium.
- Rows (owner, 2026-10-13): no card behind a row; the check circle takes the title's font and `.imageScale(.large)` on a first-baseline `HStack`, so it centers on the title's first line. DoneTick pages and the admin To-Do lay rows out in the dynamic grid; Groceries stacks.
- Departures: quick links use the glass tile face with the web color on the icon and border rather than a 72% color fill (text contrast on the material, HIG: Materials); due tones put the color on a symbol and keep label-colored text (4.5:1 on the material); due date and time are optional toggles with native pickers instead of empty date fields; Specific Days of Week is a checkmark list instead of a multi-select box.
- Split view on iPad and unfolded Duo landscape (quick links primary, sub-page secondary) waits for the navigation shell's `OnDemandSplitStack` (PR #3); until then sub-pages push full width everywhere.
- Debug gallery: `FENTON_GALLERY=chores` (+ `FENTON_GALLERY_TODO_PAGE=<route>`, `FENTON_GALLERY_VIEWER=steph`, `FENTON_GALLERY_EMPTY=1`) with a fixture service that applies check-offs, adds, renames and deletes.

## Tests

- Unit: `ChoresConfigTests`, `TodoItemTests`, `TodoListControllerTests` (+ optimistic statuses, store, cache), `DonetickTaskFormTests`, `TodoServicingTests` (websocket and `return_response` over `HAMockConnection`, multipart upload).
- Hosted: `ChoresViewTests` (every page full and empty, rows, sheets, layout policy, due bindings, model).
- Journeys (`ChoresJourneyTests`, gallery fixtures, never the house): quick links and navigation, check-off, edit and create task, groceries add/check-off, admin rename and completion script, empty state, audits with AX5 relaunch on the tab, every sub-page and every sheet; plus a read-only signed-in pass of the real tab.
