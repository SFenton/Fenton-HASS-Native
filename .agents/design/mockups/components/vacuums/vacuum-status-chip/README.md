# Vacuum status chip, order badge, setting row, action rows (component)
> **What:** the small vacuum sheet parts: status chip, order chip and badge, setting rows, dock action rows, command buttons. **Read when:** you change `VacuumComponents.swift` or a vacuum control.
- Mockup: [vacuum-status-chip.html](vacuum-status-chip.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Vacuums/VacuumComponents.swift, VacuumMapPanel.swift, VacuumTabs.swift` (paths under `apple/Sources/` unless full) · Spec: `.agents/patterns/vacuum-sheet.md, status-pill.md` · Patterns: vacuum-sheet, status-pill, module-list
- States covered: status by state, battery by level, dock status, order chip, badge, room cards, setting rows (beside, under, menu, disabled), action rows, command buttons, ax5
- Motion: chip tone (0.6 s)
- Devices: compact and regular width (sheet surface, light and dark)
- Open notes: tab and runtime copy comes from VacuumController; promote the vac.* builders to the kit
