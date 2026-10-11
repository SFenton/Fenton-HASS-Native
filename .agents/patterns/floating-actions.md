# Floating actions and filter sheets

> **What:** page-level floating buttons (Add Task, Add Groceries, Scan Item, recipe/inventory Search, Sort, Filter) and the sort/filter sheets they open. **Read when:** a page has a web `DashboardFloatingAction` or a sort/filter modal.

- One bar per page: `.floatingActionBar([FloatingAction], search: FloatingSearch?)` on the page's scroll view. It uses `safeAreaInset(edge: .bottom, alignment: .trailing)`, so the last row scrolls clear of the bar; never overlay it by hand.
- `FloatingAction(showsTitle: true)` is the labeled capsule (the web's primary FAB: "Add Task", "Add Groceries", "Scan Item"); `showsTitle: false` is a 52 pt icon circle (Sort, Filter, icon-only Scan) that keeps its title as the VoiceOver label. `isActive` draws the active brown and adds `.isSelected` (a sort or filter is applied).
- Search (`FloatingSearch`) starts as a magnifier circle; expanded it takes the bar's width and hides the other actions (web recipe/inventory search). Close clears the text and collapses.
- Colors: the web's `CHORE_BLUE` (0,154,199) and active brown (155,110,64) fail 4.5:1 under white labels, so the bar uses (0,110,145) and (135,95,55) (`FloatingActionBarTests.tintsKeepWhiteTextReadable`). Record any other tint the same way.
- Sort/filter modals use `FilterSheet(title:canApply:canReset:onApply:onReset:)`: the caller owns a draft, Apply commits it and closes, Cancel drops it, "Reset to Defaults" restores defaults in the draft only. Single-choice options are `FilterOptionRow` (title, subtitle, checkmark, `.isSelected`); sliders and toggles are plain `Slider` / `Toggle` rows with an `accessibilityValue`.
- Debug gallery: `FENTON_GALLERY=floating-actions` (journeys in `FloatingActionsJourneyTests`).
