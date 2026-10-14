# Vacuum sheet

> **What:** the robot vacuum sheet (map, status, Controls/Rooms/Auto-Clean/Dock/Info tabs, area editor, cleaning report). **Read when:** opening a vacuum from any screen or changing vacuum controls.

Web source: `ha-sfenton-react-dash@9ac2a46:src/components/hass/VacuumCard.tsx`, `vacuumModalRuntime.ts`, `vacuumStatus.ts`, `VacuumOutcomes.tsx`; config `src/constants/portedDashboard.ts`.

| Piece | File |
|---|---|
| Config (Main Floor, Music Room, Theater Room; auto-clean controls) | `HassCore/Config/VacuumConfig.swift` |
| Status contract, runtime mode, tabs | `HassCore/Vacuums/VacuumStatus.swift` |
| While-away report parsing and reconciliation | `HassCore/Vacuums/VacuumOutcomes.swift` |
| Commands, rooms, settings, queued clean | `HassCore/Vacuums/VacuumController.swift` |
| Auto-Clean tiles | `HassCore/Vacuums/VacuumAutoCleanController.swift` |
| Sheet, layout, navigation | `HassUI/Features/Vacuums/VacuumSheet.swift` |
| Tabs | `HassUI/Features/Vacuums/VacuumTabs.swift` |
| Map panel, status summary, report | `HassUI/Features/Vacuums/VacuumMapPanel.swift` |
| Area editor | `HassUI/Features/Vacuums/VacuumAreaEditor.swift` |
| Buttons, rows, notices | `HassUI/Features/Vacuums/VacuumComponents.swift` |

## Using it

```swift
.sheet(item: $vacuum) { vacuum in
    VacuumSheet(vacuum: vacuum, connection: connection)
        .hassSheet(.page)
}
```

## Behavior

- **Runtime mode** (`VacuumRuntime`): full when docked or idle and ready; minimal while cleaning, paused, returning or resumable. Rooms, auto-clean rooms and settings lock outside full mode; the Dock tab shows only the active dock cycle in minimal mode.
- **Settings and rooms are intents.** Each change shows at once, sends `select_option` or `turn_on/off`, and reverts after 8 s unless Home Assistant confirms. Turning a room on picks `vacuum` or `vacuum_and_mop` from the selected rooms' `mop_required` hints.
- **Clean waits for settled settings.** With an unconfirmed intent the clean is queued; it starts once every intent confirms and the store has been quiet for 0.65 s. It fails with a message if settings never confirm (8 s), the vacuum stops being ready, Home Assistant rejects the script, or the robot does not start cleaning within 30 s.
- **Rooms or Area.** Area cleaning (Main Floor) and room selection exclude each other; switching asks first and clears the other. Areas are drawn in the area editor and sent in centimetres (`x_min_cm`…).
- **Smooth tab and mode changes.** The tab column draws a displayed key (tab + runtime mode) through `SmoothContentSwap`: a tab change fades the old tab out (0.13 s), swaps it while hidden and fades the new one in (0.17 s), like the web's `useSmoothDisplayedModalTab`. Starting or ending a clean (full ⇄ minimal) does the same with a layout animation between, so the setup collapses and the tab control drops or regains Rooms while the content is hidden (web `useVacuumRuntimeContentTransition`). The outgoing mode keeps drawing as it fades: `VacuumControlsTab(mode:)` reads `powerSettings(in:)` / `showsCleaningSetup(in:)`, and the new mode's runtime actions wait for the swap. Reduce Motion swaps at once.
- **Tab state lives outside the sheet's body** (`VacuumSheetContent`), so a tab change redraws only the tab column and never the map canvas. A tab change scrolls the column back to the tab control only when the control is under the bar or above it.
- **Setting rows** are an icon and title with a trailing `Menu` (inline `Picker` inside, 44 pt label); only the value is the menu's source, because iOS hides a menu's source while it is open (a whole-row `Menu` label made the row vanish).
- **Room and auto-clean cards** are at least 76 pt tall with a `.title2` icon and body-weight title; room cards put the icon and order badge above the title, and every card in a grid row matches the tallest (larger than the web's 58 px, owner 2026-10-13).
- **Two columns** only where splits are allowed and the sheet is wide (`MediaRemoteLayout.usesTwoColumns`): map and status on the left, tabs on the right.
- **Accessibility:** room buttons are toggles with their order in the label; the map is decorative (rooms are also on the Rooms tab); the area editor offers Draw (a default area under VoiceOver) and move, grow and shrink actions; every control is at least 44 pt.
