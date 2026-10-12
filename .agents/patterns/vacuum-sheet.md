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
        .vacuumPresentation()
}
```

## Behavior

- **Runtime mode** (`VacuumRuntime`): full when docked or idle and ready; minimal while cleaning, paused, returning or resumable. Rooms, auto-clean rooms and settings lock outside full mode; the Dock tab shows only the active dock cycle in minimal mode.
- **Settings and rooms are intents.** Each change shows at once, sends `select_option` or `turn_on/off`, and reverts after 8 s unless Home Assistant confirms. Turning a room on picks `vacuum` or `vacuum_and_mop` from the selected rooms' `mop_required` hints.
- **Clean waits for settled settings.** With an unconfirmed intent the clean is queued; it starts once every intent confirms and the store has been quiet for 0.65 s. It fails with a message if settings never confirm (8 s), the vacuum stops being ready, Home Assistant rejects the script, or the robot does not start cleaning within 30 s.
- **Rooms or Area.** Area cleaning (Main Floor) and room selection exclude each other; switching asks first and clears the other. Areas are drawn in the area editor and sent in centimetres (`x_min_cm`…).
- **Two columns** only where splits are allowed and the sheet is wide (`MediaRemoteLayout.usesTwoColumns`): map and status on the left, tabs on the right.
- **Accessibility:** room buttons are toggles with their order in the label; the map is decorative (rooms are also on the Rooms tab); the area editor offers Draw (a default area under VoiceOver) and move, grow and shrink actions; every control is at least 44 pt.
