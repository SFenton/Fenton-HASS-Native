# Switch to Rooms / Area (confirmation) (modal)
> **What:** the confirmation dialog and alert that guard switching between Rooms and Area. **Read when:** you change the dialog copy in `VacuumTabs.swift` or `VacuumMapPanel.swift`.
- Mockup: [vacuum-switch-dialog.html](vacuum-switch-dialog.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Vacuums/VacuumTabs.swift, VacuumMapPanel.swift, HassCore/Vacuums/VacuumController.swift` (paths under `apple/Sources/` unless full) · Spec: `.agents/patterns/vacuum-sheet.md, .agents/pages/vacuums/spec.md` · Patterns: vacuum-sheet, modal-sheet
- States covered: Switch to Rooms and Switch to Area? dialogs, alert on the Rooms section and on the map, offline, large, closed, ax5; loading/error noted as none
- Motion: none; transitions: dialog and alert present
- Devices: iPhone, Duo folded, Duo unfolded landscape, iPad portrait and landscape
- Open notes: titles disagree ("Switch to Rooms" vs "Switch to Area?"); the alert is duplicated in two views (review findings)
